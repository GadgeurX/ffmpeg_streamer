import 'dart:async';
import 'dart:collection';
import 'package:ffmpeg_streamer/ffmpeg_streamer.dart';
import 'package:flutter/foundation.dart';

/// Represents a batch of video frames in memory
class FrameBatch {
  final int startFrame;
  final int endFrame;
  final Map<int, VideoFrame> frames;
  final DateTime loadedAt;
  bool isLoading;

  FrameBatch({
    required this.startFrame,
    required this.endFrame,
    required this.frames,
    required this.loadedAt,
    this.isLoading = false,
  });

  bool containsFrame(int frameIndex) {
    return frameIndex >= startFrame && frameIndex <= endFrame && frames.containsKey(frameIndex);
  }

  bool isInRange(int frameIndex) {
    return frameIndex >= startFrame && frameIndex <= endFrame;
  }

  int get frameCount => frames.length;
  
  bool get isEmpty => frames.isEmpty;
}

/// Configuration for the batch manager
class BatchManagerConfig {
  /// Size of each batch (number of frames)
  final int batchSize;
  
  /// Number of frames before the batch boundary to trigger preloading
  final int preloadThreshold;
  
  /// Maximum number of batches to keep in memory
  final int maxCachedBatches;
  
  /// Distance (in frames) beyond which batches are considered too far and can be freed
  final int maxDistanceForCache;

  const BatchManagerConfig({
    this.batchSize = 30,
    this.preloadThreshold = 5,
    this.maxCachedBatches = 5,
    this.maxDistanceForCache = 150,
  });
}

/// Manages frame batches with intelligent preloading and memory management
class FrameBatchManager {
  final FfmpegDecoder decoder;
  final int totalFrames;
  final BatchManagerConfig config;

  /// Cache of loaded batches, ordered by access time (LRU)
  final LinkedHashMap<int, FrameBatch> _batchCache = LinkedHashMap();
  
  /// Currently loading batch IDs
  final Set<int> _loadingBatches = {};
  
  /// Pending batch requests
  int? _currentRequestId;
  
  /// Stream controller for batch loading events
  final _batchLoadController = StreamController<FrameBatchEvent>.broadcast();
  
  /// Listen to batch loading events
  Stream<FrameBatchEvent> get batchLoadStream => _batchLoadController.stream;

  FrameBatchManager({
    required this.decoder,
    required this.totalFrames,
    this.config = const BatchManagerConfig(),
  });

  /// Get the batch ID for a given frame index
  int _getBatchId(int frameIndex) {
    return frameIndex ~/ config.batchSize;
  }

  /// Get the start frame for a batch
  int _getBatchStartFrame(int batchId) {
    return batchId * config.batchSize;
  }

  /// Get the end frame for a batch
  int _getBatchEndFrame(int batchId) {
    final endFrame = ((batchId + 1) * config.batchSize) - 1;
    return endFrame.clamp(0, totalFrames - 1);
  }

  /// Get a frame, loading its batch if necessary
  Future<VideoFrame?> getFrame(int frameIndex) async {
    if (frameIndex < 0 || frameIndex >= totalFrames) {
      return null;
    }

    final batchId = _getBatchId(frameIndex);
    
    // Check if frame is already in cache
    if (_batchCache.containsKey(batchId)) {
      final batch = _batchCache[batchId]!;
      if (batch.containsFrame(frameIndex)) {
        // Move to end (mark as recently used)
        _batchCache.remove(batchId);
        _batchCache[batchId] = batch;
        
        // Check if we need to preload adjacent batches
        _checkPreloading(frameIndex, batchId);
        
        // Clean up distant batches
        _cleanupDistantBatches(frameIndex);
        
        return batch.frames[frameIndex];
      } else if (batch.isLoading) {
        // Batch is loading, wait for the specific frame
        int attempts = 0;
        const maxAttempts = 100; // 10 seconds max
        while (attempts < maxAttempts) {
          await Future.delayed(const Duration(milliseconds: 100));
          if (batch.containsFrame(frameIndex)) {
            return batch.frames[frameIndex];
          }
          attempts++;
        }
        debugPrint('⚠️ Timeout waiting for frame $frameIndex in batch $batchId');
        return null;
      }
    }

    // Need to load the batch
    await _loadBatch(batchId);
    
    // Check preloading after loading
    _checkPreloading(frameIndex, batchId);
    
    // Return the frame
    final batch = _batchCache[batchId];
    return batch?.frames[frameIndex];
  }

  /// Load a batch of frames
  Future<void> _loadBatch(int batchId) async {
    // Check if already loading or loaded
    if (_loadingBatches.contains(batchId) || _batchCache.containsKey(batchId)) {
      return;
    }

    _loadingBatches.add(batchId);
    
    final startFrame = _getBatchStartFrame(batchId);
    final endFrame = _getBatchEndFrame(batchId);

    debugPrint('📦 Loading batch $batchId: frames $startFrame to $endFrame');
    
    _batchLoadController.add(FrameBatchEvent(
      type: BatchEventType.loadingStarted,
      batchId: batchId,
      startFrame: startFrame,
      endFrame: endFrame,
    ));

    try {
      // Create batch placeholder
      final batch = FrameBatch(
        startFrame: startFrame,
        endFrame: endFrame,
        frames: {},
        loadedAt: DateTime.now(),
        isLoading: true,
      );

      _batchCache[batchId] = batch;

      // Load frames using range request
      final completer = Completer<void>();
      int loadedCount = 0;
      final expectedCount = endFrame - startFrame + 1;

      _currentRequestId = decoder.getFramesRangeByIndexAsync(
        startFrame,
        endFrame,
        (mediaFrame) {
          if (mediaFrame?.video != null) {
            final frame = mediaFrame!.video!;
            // Store frame using its actual index
            final frameIndex = startFrame + loadedCount;
            batch.frames[frameIndex] = frame;
            loadedCount++;
            
            // Complete when all frames are loaded
            if (loadedCount >= expectedCount && !completer.isCompleted) {
              completer.complete();
            }
          }
        },
        progressCallback: (current, total) {
          _batchLoadController.add(FrameBatchEvent(
            type: BatchEventType.loadingProgress,
            batchId: batchId,
            startFrame: startFrame,
            endFrame: endFrame,
            progress: current / total,
          ));
        },
      );

      // Wait for all frames to be loaded or timeout
      await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('⚠️ Timeout loading batch $batchId, loaded $loadedCount/$expectedCount frames');
        },
      );
      
      // Mark as loaded
      batch.isLoading = false;
      _loadingBatches.remove(batchId);

      debugPrint('✅ Batch $batchId loaded: ${batch.frameCount} frames');
      
      _batchLoadController.add(FrameBatchEvent(
        type: BatchEventType.loadingCompleted,
        batchId: batchId,
        startFrame: startFrame,
        endFrame: endFrame,
        frameCount: batch.frameCount,
      ));

      // Clean up old batches if we exceed the limit
      _enforceMaxCachedBatches();
    } catch (e) {
      _loadingBatches.remove(batchId);
      _batchCache.remove(batchId);
      
      debugPrint('❌ Error loading batch $batchId: $e');
      
      _batchLoadController.add(FrameBatchEvent(
        type: BatchEventType.loadingFailed,
        batchId: batchId,
        startFrame: startFrame,
        endFrame: endFrame,
        error: e.toString(),
      ));
    }
  }

  /// Check if we need to preload adjacent batches
  void _checkPreloading(int currentFrame, int currentBatchId) {
    final batch = _batchCache[currentBatchId];
    if (batch == null) return;

    // Calculate distance from batch boundaries
    final distanceFromStart = currentFrame - batch.startFrame;
    final distanceFromEnd = batch.endFrame - currentFrame;

    // Preload previous batch if close to start
    if (distanceFromStart < config.preloadThreshold) {
      final prevBatchId = currentBatchId - 1;
      if (prevBatchId >= 0 && !_batchCache.containsKey(prevBatchId) && !_loadingBatches.contains(prevBatchId)) {
        debugPrint('🔮 Preloading previous batch $prevBatchId');
        _loadBatch(prevBatchId);
      }
    }

    // Preload next batch if close to end
    if (distanceFromEnd < config.preloadThreshold) {
      final nextBatchId = currentBatchId + 1;
      final nextBatchStart = _getBatchStartFrame(nextBatchId);
      if (nextBatchStart < totalFrames && !_batchCache.containsKey(nextBatchId) && !_loadingBatches.contains(nextBatchId)) {
        debugPrint('🔮 Preloading next batch $nextBatchId');
        _loadBatch(nextBatchId);
      }
    }
  }

  /// Clean up batches that are too far from the current frame
  void _cleanupDistantBatches(int currentFrame) {
    final toRemove = <int>[];

    for (final entry in _batchCache.entries) {
      final batchId = entry.key;
      final batch = entry.value;

      // Calculate distance from current frame to batch
      final distanceToStart = (currentFrame - batch.startFrame).abs();
      final distanceToEnd = (currentFrame - batch.endFrame).abs();
      final minDistance = distanceToStart < distanceToEnd ? distanceToStart : distanceToEnd;

      // Mark for removal if too far
      if (minDistance > config.maxDistanceForCache) {
        toRemove.add(batchId);
      }
    }

    // Remove distant batches
    for (final batchId in toRemove) {
      final batch = _batchCache.remove(batchId);
      if (batch != null) {
        debugPrint('🗑️ Cleaning up distant batch $batchId (${batch.frameCount} frames)');
        _batchLoadController.add(FrameBatchEvent(
          type: BatchEventType.batchRemoved,
          batchId: batchId,
          startFrame: batch.startFrame,
          endFrame: batch.endFrame,
        ));
      }
    }
  }

  /// Enforce maximum number of cached batches (LRU eviction)
  void _enforceMaxCachedBatches() {
    while (_batchCache.length > config.maxCachedBatches) {
      // Remove least recently used (first in LinkedHashMap)
      final oldestBatchId = _batchCache.keys.first;
      final batch = _batchCache.remove(oldestBatchId);
      
      if (batch != null) {
        debugPrint('🗑️ Evicting LRU batch $oldestBatchId (${batch.frameCount} frames)');
        _batchLoadController.add(FrameBatchEvent(
          type: BatchEventType.batchRemoved,
          batchId: oldestBatchId,
          startFrame: batch.startFrame,
          endFrame: batch.endFrame,
        ));
      }
    }
  }

  /// Get cache statistics
  CacheStats getCacheStats() {
    int totalFramesInCache = 0;
    for (final batch in _batchCache.values) {
      totalFramesInCache += batch.frameCount;
    }

    return CacheStats(
      cachedBatches: _batchCache.length,
      loadingBatches: _loadingBatches.length,
      totalFramesInCache: totalFramesInCache,
      memoryUsageMB: (totalFramesInCache * 1920 * 1080 * 4) / (1024 * 1024), // Rough estimate
    );
  }

  /// Clear all cached batches
  void clearCache() {
    debugPrint('🧹 Clearing all cached batches');
    final batchIds = _batchCache.keys.toList();
    
    for (final batchId in batchIds) {
      final batch = _batchCache.remove(batchId);
      if (batch != null) {
        _batchLoadController.add(FrameBatchEvent(
          type: BatchEventType.batchRemoved,
          batchId: batchId,
          startFrame: batch.startFrame,
          endFrame: batch.endFrame,
        ));
      }
    }
    
    _loadingBatches.clear();
  }

  /// Preload a specific range of frames
  Future<void> preloadRange(int startFrame, int endFrame) async {
    final startBatchId = _getBatchId(startFrame);
    final endBatchId = _getBatchId(endFrame);

    debugPrint('📦 Preloading range: frames $startFrame to $endFrame (batches $startBatchId to $endBatchId)');

    for (int batchId = startBatchId; batchId <= endBatchId; batchId++) {
      if (!_batchCache.containsKey(batchId) && !_loadingBatches.contains(batchId)) {
        await _loadBatch(batchId);
      }
    }
  }

  /// Dispose resources
  void dispose() {
    clearCache();
    _batchLoadController.close();
  }
}

/// Event types for batch operations
enum BatchEventType {
  loadingStarted,
  loadingProgress,
  loadingCompleted,
  loadingFailed,
  batchRemoved,
}

/// Event emitted during batch operations
class FrameBatchEvent {
  final BatchEventType type;
  final int batchId;
  final int startFrame;
  final int endFrame;
  final double? progress;
  final int? frameCount;
  final String? error;

  FrameBatchEvent({
    required this.type,
    required this.batchId,
    required this.startFrame,
    required this.endFrame,
    this.progress,
    this.frameCount,
    this.error,
  });
}

/// Cache statistics
class CacheStats {
  final int cachedBatches;
  final int loadingBatches;
  final int totalFramesInCache;
  final double memoryUsageMB;

  CacheStats({
    required this.cachedBatches,
    required this.loadingBatches,
    required this.totalFramesInCache,
    required this.memoryUsageMB,
  });

  @override
  String toString() {
    return 'CacheStats(batches: $cachedBatches, loading: $loadingBatches, frames: $totalFramesInCache, memory: ${memoryUsageMB.toStringAsFixed(1)}MB)';
  }
}
