import sounddevice as sd, numpy as np, tempfile, os, wave, sys, time, argparse

def main(duration=5):
    fs = 16000
    print("Recording...")
    rec = sd.rec(int(duration * fs), samplerate=fs, channels=1, dtype='int16')
    sd.wait()

    tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
    tmp.close()
    with wave.open(tmp.name, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(fs)
        w.writeframes(rec.tobytes())

    from faster_whisper import WhisperModel
    model = WhisperModel("base", device="cpu", compute_type="int8")
    segs, _ = model.transcribe(tmp.name, language="ru", beam_size=5)
    text = " ".join(s.text for s in segs).strip()
    os.unlink(tmp.name)

    if text:
        # Экранирование спецсимволов для SendKeys
        for ch, rep in [("{", "{{"), ("}", "}}"), ("+", "{+}"), ("^", "{^}"),
                        ("%", "{%}"), ("~", "{~}"), ("\n", "{Enter}")]:
            text = text.replace(ch, rep)
        # PowerShell SendKeys в активное окно
        import subprocess
        ps_code = f'Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait("{text}")'
        subprocess.run(["powershell", "-NoProfile", "-Command", ps_code], capture_output=True)
        print(f"Sent: {text[:60]}...")
    else:
        print("Silence - nothing transcribed")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("-d", "--duration", type=int, default=5, help="Recording duration in seconds")
    args = parser.parse_args()
    main(args.duration)
