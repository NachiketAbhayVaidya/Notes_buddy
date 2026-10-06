import io
import os
import re
import time
from collections import defaultdict, deque
from xml.sax.saxutils import escape

from dotenv import load_dotenv
from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.responses import PlainTextResponse, Response
from google import genai
from pydantic import BaseModel
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.lib.units import cm
from reportlab.platypus import ListFlowable, ListItem, PageBreak, Paragraph, SimpleDocTemplate, Spacer

load_dotenv()
MODELS = [os.getenv("GEMINI_MODEL", "gemini-3.8-flash"), "gemini-3.7-flash", "gemini-3.5-flash", "gemini-3.1-flash-lite"]

APP_KEY = os.getenv("APP_KEY")
RATE_LIMIT, RATE_WINDOW = 5, 60  # requests per window, per client IP
_hits = defaultdict(deque)

app = FastAPI(title="Notifyy backend")
_client = None


def client() -> genai.Client:
    global _client
    if _client is None:
        key = os.getenv("GEMINI_API_KEY")
        if not key:
            raise HTTPException(500, "GEMINI_API_KEY is not set in backend/.env")
        _client = genai.Client(api_key=key)
    return _client


class NotesRequest(BaseModel):
    topic: str


PROMPT = """Write detailed, well-structured study notes about: "{topic}".
Length: at least 4500 words in total. Write exactly 10 sections, each at least 400 words, with examples. Use ONLY this simple format:
- "# " for the title (once, first line)
- "## " for each section heading (exactly 10 sections)
- plain paragraphs for explanations
- "- " for bullet points
Include definitions, key concepts, examples, and a short summary at the end.
No tables, no code fences, no bold/italic markers."""


def inline(text: str) -> str:
    return escape(text.replace("**", "").replace("`", ""))


def build_pdf(markdown: str, topic: str) -> bytes:
    styles = getSampleStyleSheet()
    story, bullets = [], []

    def flush():
        if bullets:
            story.append(ListFlowable([ListItem(Paragraph(b, styles["BodyText"])) for b in bullets],
                                      bulletType="bullet", leftIndent=18))
            bullets.clear()

    for raw in markdown.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("## "):
            flush()
            story += [Spacer(1, 10), Paragraph(inline(line[3:]), styles["Heading2"])]
        elif line.startswith("# "):
            flush()
            story += [Paragraph(inline(line[2:]), styles["Title"]), Spacer(1, 8)]
        elif re.match(r"^[-*] ", line):
            bullets.append(inline(line[2:]))
        else:
            flush()
            story += [Paragraph(inline(line), styles["BodyText"]), Spacer(1, 4)]
    flush()
    if not story:
        story = [Paragraph(inline(topic), styles["Title"])]

    buf = io.BytesIO()
    SimpleDocTemplate(buf, pagesize=A4, leftMargin=2 * cm, rightMargin=2 * cm,
                      topMargin=2 * cm, bottomMargin=2 * cm, title=topic).build(story)
    return buf.getvalue()


@app.get("/ping", response_class=PlainTextResponse)
def ping():
    return "pong"


@app.post("/generate-notes")
def generate_notes(req: NotesRequest, request: Request, x_app_key: str | None = Header(default=None)):
    if APP_KEY and x_app_key != APP_KEY:
        raise HTTPException(401, "Invalid app key")
    ip = request.headers.get("x-forwarded-for", request.client.host).split(",")[0].strip()
    now = time.time()
    q = _hits[ip]
    while q and now - q[0] > RATE_WINDOW:
        q.popleft()
    if len(q) >= RATE_LIMIT:
        raise HTTPException(429, "Too many requests, wait a minute")
    q.append(now)
    topic = req.topic.strip()
    if not topic:
        raise HTTPException(400, "topic is empty")
    resp, last = None, None
    for attempt in range(3):
        for model in MODELS:
            try:
                resp = client().models.generate_content(model=model, contents=PROMPT.format(topic=topic))
                break
            except HTTPException:
                raise
            except Exception as e:
                last = e
                if not any(c in str(e) for c in ("503", "429", "500", "404")):
                    raise HTTPException(502, f"Gemini error: {e}")
        if resp:
            break
        time.sleep(5 * (attempt + 1))
    if resp is None:
        raise HTTPException(503, f"Gemini is busy, try again shortly. Last error: {last}")
    if not resp.text:
        raise HTTPException(502, "Gemini returned no text")
    return Response(build_pdf(resp.text, topic), media_type="application/pdf")
