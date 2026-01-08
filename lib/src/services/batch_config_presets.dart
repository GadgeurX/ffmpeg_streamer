import 'frame_batch_manager.dart';

/// Predefined configurations for different use cases
class BatchConfigPresets {
  BatchConfigPresets._();

  /// Default configuration - balanced for most use cases
  /// - Works well for 1080p videos
  /// - Moderate memory usage (~1.25 GB)
  /// - Good playback performance
  static const BatchManagerConfig standard = BatchManagerConfig(
    batchSize: 30,
    preloadThreshold: 5,
    maxCachedBatches: 5,
    maxDistanceForCache: 150,
  );

  /// High performance configuration for smooth playback
  /// - Larger batches for fewer loading pauses
  /// - Aggressive preloading
  /// - More cache for seamless experience
  /// - Higher memory usage (~2.5 GB for 1080p)
  static const BatchManagerConfig highPerformance = BatchManagerConfig(
    batchSize: 90,           // 3 seconds at 30fps
    preloadThreshold: 15,    // Preload 0.5s ahead
    maxCachedBatches: 10,
    maxDistanceForCache: 500,
  );

  /// Memory efficient configuration for limited devices
  /// - Smaller batches to reduce memory footprint
  /// - Minimal preloading
  /// - Aggressive cleanup
  /// - Lower memory usage (~375 MB for 1080p)
  static const BatchManagerConfig memoryEfficient = BatchManagerConfig(
    batchSize: 15,
    preloadThreshold: 3,
    maxCachedBatches: 3,
    maxDistanceForCache: 60,
  );

  /// Configuration optimized for 4K videos
  /// - Very small batches due to large frame size
  /// - Minimal cache to prevent OOM
  /// - Quick cleanup
  /// - Memory usage (~1.5 GB for 4K)
  static const BatchManagerConfig video4K = BatchManagerConfig(
    batchSize: 10,
    preloadThreshold: 2,
    maxCachedBatches: 3,
    maxDistanceForCache: 50,
  );

  /// Configuration for timeline scrubbing
  /// - Medium batches for quick access
  /// - Wide preloading for smooth scrubbing
  /// - Keep more batches for bidirectional movement
  /// - Moderate memory usage (~2 GB for 1080p)
  static const BatchManagerConfig scrubbing = BatchManagerConfig(
    batchSize: 45,
    preloadThreshold: 10,
    maxCachedBatches: 8,
    maxDistanceForCache: 200,
  );

  /// Configuration for editing workflow
  /// - Balanced for jumping between points
  /// - Moderate preloading
  /// - Good cache size for working area
  /// - Moderate memory usage (~1.5 GB for 1080p)
  static const BatchManagerConfig editing = BatchManagerConfig(
    batchSize: 30,
    preloadThreshold: 8,
    maxCachedBatches: 6,
    maxDistanceForCache: 180,
  );

  /// Configuration for slow playback / analysis
  /// - Smaller batches for fine control
  /// - Less preloading (slower playback)
  /// - More batches for longer sequences
  /// - Lower memory usage (~1 GB for 1080p)
  static const BatchManagerConfig slowMotion = BatchManagerConfig(
    batchSize: 20,
    preloadThreshold: 4,
    maxCachedBatches: 6,
    maxDistanceForCache: 120,
  );

  /// Get recommended config based on video properties
  static BatchManagerConfig getRecommendedConfig({
    required int width,
    required int height,
    required int totalFrames,
    int? availableMemoryMB,
  }) {
    // Calculate frame size in MB
    final frameSizeMB = (width * height * 4) / (1024 * 1024);
    
    // Determine if 4K
    final is4K = width >= 3840 || height >= 2160;
    
    // Determine if HD
    final isHD = width >= 1920 || height >= 1080;
    
    // Check available memory if provided
    if (availableMemoryMB != null && availableMemoryMB < 2048) {
      // Less than 2GB available
      return memoryEfficient;
    }
    
    // Choose based on resolution
    if (is4K) {
      return video4K;
    } else if (isHD) {
      return standard;
    } else {
      // SD or lower - can use high performance
      return highPerformance;
    }
  }

  /// Create a custom configuration by modifying a preset
  static BatchManagerConfig customize({
    required BatchManagerConfig base,
    int? batchSize,
    int? preloadThreshold,
    int? maxCachedBatches,
    int? maxDistanceForCache,
  }) {
    return BatchManagerConfig(
      batchSize: batchSize ?? base.batchSize,
      preloadThreshold: preloadThreshold ?? base.preloadThreshold,
      maxCachedBatches: maxCachedBatches ?? base.maxCachedBatches,
      maxDistanceForCache: maxDistanceForCache ?? base.maxDistanceForCache,
    );
  }

  /// Get estimated memory usage for a configuration
  /// Returns memory usage in MB for 1080p video
  static double estimateMemoryUsage1080p(BatchManagerConfig config) {
    // 1920x1080x4 bytes per frame
    const frameSizeMB = (1920 * 1080 * 4) / (1024 * 1024);
    final framesPerBatch = config.batchSize;
    final maxBatches = config.maxCachedBatches;
    
    return frameSizeMB * framesPerBatch * maxBatches;
  }

  /// Get estimated memory usage for any resolution
  static double estimateMemoryUsage({
    required BatchManagerConfig config,
    required int width,
    required int height,
  }) {
    final frameSizeMB = (width * height * 4) / (1024 * 1024);
    final framesPerBatch = config.batchSize;
    final maxBatches = config.maxCachedBatches;
    
    return frameSizeMB * framesPerBatch * maxBatches;
  }
}

/// Extension for easy preset descriptions
extension BatchConfigPresetDescription on BatchManagerConfig {
  /// Get a human-readable description of the configuration
  String get description {
    if (this == BatchConfigPresets.standard) {
      return 'Standard - Balanced performance';
    } else if (this == BatchConfigPresets.highPerformance) {
      return 'High Performance - Smooth playback';
    } else if (this == BatchConfigPresets.memoryEfficient) {
      return 'Memory Efficient - Limited devices';
    } else if (this == BatchConfigPresets.video4K) {
      return '4K Optimized - Large frames';
    } else if (this == BatchConfigPresets.scrubbing) {
      return 'Scrubbing - Timeline navigation';
    } else if (this == BatchConfigPresets.editing) {
      return 'Editing - Workflow optimized';
    } else if (this == BatchConfigPresets.slowMotion) {
      return 'Slow Motion - Frame analysis';
    } else {
      return 'Custom configuration';
    }
  }

  /// Get estimated memory usage for 1080p
  double get estimatedMemory1080p {
    return BatchConfigPresets.estimateMemoryUsage1080p(this);
  }
}
