import sys, json, os, numpy as np
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from faster_whisper import WhisperModel
from io import BytesIO

MODEL_PATH = os.environ.get("WHISPER_MODEL_DIR") or str(Path(__file__).parent.parent / "models" / "whisper-base")
model = None

def get_model():
    global model
    if model is None:
        model = WhisperModel(MODEL_PATH, device="cpu", compute_type="int8", local_files_only=True)
    return model

RESULT_FILE = str(Path(__file__).parent.parent / "temp" / "voice_result.json")

def save_result(data):
    with open(RESULT_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=True)

def transcribe_wav(data: bytes):
    try:
        # VAD перед транскрибацией
        if len(data) > 44:
            samples = np.frombuffer(data[44:], dtype=np.int16).astype(np.float32) / 32768.0
            significant = int(np.sum(np.abs(samples) > 0.005))
            density = significant / len(samples) if len(samples) > 0 else 0
            if density < 0.001:
                r = {"silence": True, "density": round(density, 6)}
                save_result(r)
                return r

        segs, info = get_model().transcribe(BytesIO(data), beam_size=5, language="ru")
        text = " ".join(s.text for s in segs).strip()
        r = {"text": text}
        save_result(r)
        return r
    except Exception as e:
        r = {"error": str(e)}
        save_result(r)
        return r

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/":
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            html_path = Path(__file__).parent / "voice_recorder.html"
            self.wfile.write(html_path.read_bytes())
        else:
            self.send_response(404); self.end_headers()

    def do_POST(self):
        if self.path == "/upload":
            clen = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(clen)
            result = transcribe_wav(body)
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(json.dumps(result, ensure_ascii=True).encode("utf-8"))
        else:
            self.send_response(404); self.end_headers()

    def log_message(self, fmt, *args):
        print(f"[voice] {args[0]}", flush=True)

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    print(f"Voice server: http://localhost:{port}", flush=True)
    print("Откройте в браузере на удалённом ПК. Запись -> Стоп -> текст готов.", flush=True)
    HTTPServer(("127.0.0.1", port), Handler).serve_forever()
