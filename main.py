from fastapi import FastAPI
from fastapi.responses import FileResponse
from ai_notes import generate_notes
from pdf_generator import create_pdf
import uuid
import os

app = FastAPI()

@app.get("/ping")
def ping():
    return {"msg": "pong"}

@app.post("/generate-notes")
async def generate_notes_api(data: dict):
    topic = data.get("topic")
    if not topic:
        return {"error": "No topic provided"}

    # 1. Generate notes using AI
    notes_text = generate_notes(topic)

    # 2. Create PDF filename
    filename = f"{uuid.uuid4()}.pdf"
    filepath = os.path.join(".", filename)

    # 3. Generate PDF
    create_pdf(notes_text, filepath)

    # 4. Return PDF file to Flutter
    return FileResponse(
        path=filepath,
        media_type="application/pdf",
        filename=f"{topic}.pdf"
    )
