import 'package:audioplayers/audioplayers.dart';

abstract class IAudioPlayer {
  Future<void> setAsset(String assetPath);
  Future<void> play();
  Future<void> stop();
  Future<void> dispose();
  Future<void> seek(Duration duration);
}

abstract class AudioFactory {
  IAudioPlayer createPlayer({String? debugLabel});
}

class RealAudioFactory implements AudioFactory {
  @override
  IAudioPlayer createPlayer({String? debugLabel}) => _AudioplayersWrapper(AudioPlayer());
}

class _AudioplayersWrapper implements IAudioPlayer {
  final AudioPlayer _inner;
  _AudioplayersWrapper(this._inner);

  @override
  Future<void> setAsset(String assetPath) async => await _inner.setSource(AssetSource(assetPath.replaceFirst('assets/', '')));

  @override
  Future<void> play() async => await _inner.resume();

  @override
  Future<void> stop() async => await _inner.stop();

  @override
  Future<void> dispose() async => await _inner.dispose();
  
  @override
  Future<void> seek(Duration duration) async => await _inner.seek(duration);
}


