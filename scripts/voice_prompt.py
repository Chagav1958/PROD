import sounddevice as sd
import numpy as np
import wave
import tempfile
import os
import sys
import json
import time
from pathlib import Path
from faster_whisper import WhisperModel

WHISPER_SR = 16000

def is_mixer(name):
    n = name.lower()
    return any(x in n for x in ["stereo", "микшер", "mix", "mixer", "wave"])

def find_working_device():
    found = []
    for api_order in [3, 0]:
        for i, d in enumerate(sd.query_devices()):
            if d["hostapi"] != api_order or d["max_input_channels"] < 1:
                continue
            if is_mixer(d["name"]):
                continue
            sr = int(d["default_samplerate"])
            dtype = "int16" if d["hostapi"] == 3 else "float32"
            try:
                rec = sd.rec(int(1.5 * sr), samplerate=sr, channels=1, dtype=dtype, device=i)
                sd.wait()
                audio = rec[:, 0]
                thr = 10 if dtype == "int16" else 0.001
                # Разбиваем на 3 части по 0.5 сек, проверяем что не только первый всплеск
                part_len = int(0.5 * sr)
                ok_parts = 0
                for p in range(3):
                    start = p * part_len
                    end = start + part_len
                    if end > len(audio): break
                    mx = float(np.max(np.abs(audio[start:end])))
                    if mx > thr and not np.isnan(mx) and mx < 1e10:
                        ok_parts += 1
                if ok_parts >= 2:
                    dname = d["name"].lower()
                    score = 0
                    if "микрофон" in dname or "mic" in dname: score += 2
                    found.append((score, i, sr, d["name"], dtype))
            except:
                continue
    if found:
        found.sort(key=lambda x: -x[0])
        return found[0][1], found[0][2], found[0][3], found[0][4]
    return None, None, None, None

def resample(audio, orig_sr, target_sr):
    if orig_sr == target_sr:
        return audio
    ratio = target_sr / orig_sr
    new_len = int(len(audio) * ratio)
    return np.interp(np.linspace(0.0, len(audio)-1, new_len), np.arange(len(audio)), audio)

def save_wav(audio, filepath, sr):
    clip = np.clip(audio, -1.0, 1.0)
    audio_int16 = (clip * 32767).astype(np.int16)
    with wave.open(filepath, "w") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sr)
        wf.writeframes(audio_int16.tobytes())

def get_model_path():
    env_path = os.environ.get("WHISPER_MODEL_DIR")
    if env_path and os.path.isdir(env_path):
        return env_path
    script_dir = Path(__file__).parent.resolve()
    local_path = script_dir.parent / "models" / "whisper-base"
    if local_path.is_dir():
        return str(local_path)
    print(json.dumps({"error": "Модель не найдена"}), file=sys.stderr)
    sys.exit(1)

def main():
    dev_id, dev_sr, dev_name, dtype = find_working_device()
    if dev_id is None:
        print(json.dumps({"error": "Нет доступного микрофона"}))
        sys.exit(1)

    total_frames = int(120 * dev_sr)
    rec = sd.rec(total_frames, samplerate=dev_sr, channels=1, dtype=dtype, device=dev_id)
    print("RECORDING", flush=True)
    t_start = time.time()
    input()
    sd.stop()
    elapsed = time.time() - t_start
    actual_frames = min(int(elapsed * dev_sr) + int(dev_sr * 0.5), total_frames)

    if actual_frames < dev_sr * 0.3:
        print(json.dumps({"error": f"Нет аудиоданных. Устройство: {dev_name}", "text": ""}))
        sys.exit(0)

    audio = rec[:actual_frames, 0]
    if dtype == "int16":
        audio = audio.astype(np.float32) / 32768.0
    if dev_sr != WHISPER_SR:
        audio = resample(audio, dev_sr, WHISPER_SR)

    # VAD: детектор по плотности значащих сэмплов
    significant = int(np.sum(np.abs(audio) > 0.005))
    density = significant / len(audio) if len(audio) > 0 else 0
    if density < 0.001:
        result = {"text": "", "silence": True, "density": round(density, 6), "significant": significant}
        print(json.dumps(result, ensure_ascii=True))
        sys.exit(0)

    tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
    save_wav(audio, tmp.name, WHISPER_SR)
    tmp.close()

    try:
        print("TRANSCRIBING", flush=True)
        model_path = get_model_path()
        model = WhisperModel(model_path, device="cpu", compute_type="int8", local_files_only=True)
        segments, info = model.transcribe(tmp.name, beam_size=5, language="ru")
        text = " ".join(seg.text for seg in segments).strip()
        result = {"text": text, "language": info.language if info else "?", "duration": info.duration if info else 0}
        print(json.dumps(result, ensure_ascii=True))
    except Exception as e:
        print(json.dumps({"error": str(e), "text": ""}), file=sys.stderr)
        sys.exit(1)
    finally:
        try:
            os.unlink(tmp.name)
        except:
            pass

if __name__ == "__main__":
    main()
