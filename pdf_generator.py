from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.pagesizes import A4
from reportlab.lib import colors
from reportlab.lib.enums import TA_JUSTIFY

def create_pdf(text: str, file_path: str):
    doc = SimpleDocTemplate(
        file_path,
        pagesize=A4,
        rightMargin=40,
        leftMargin=40,
        topMargin=40,
        bottomMargin=40
    )

    styles = getSampleStyleSheet()

    # Custom styles
    title_style = ParagraphStyle(
        name='Title',
        fontSize=22,
        leading=26,
        spaceAfter=20,
        alignment=1,  # center
        textColor=colors.HexColor("#1a237e")
    )

    heading_style = ParagraphStyle(
        name='Heading',
        fontSize=16,
        leading=20,
        spaceBefore=14,
        spaceAfter=10,
        textColor=colors.HexColor("#0d47a1")
    )

    body_style = ParagraphStyle(
        name='Body',
        fontSize=11,
        leading=16,
        alignment=TA_JUSTIFY
    )

    bullet_style = ParagraphStyle(
        name='Bullet',
        fontSize=11,
        leading=14,
        leftIndent=20,
        bulletIndent=10,
    )

    story = []

    lines = text.split("\n")

    for line in lines:
        line = line.strip()

        if line.startswith("# "):
            story.append(Paragraph(line[2:], title_style))
        elif line.startswith("## "):
            story.append(Paragraph(line[3:], heading_style))
        elif line.startswith("- "):
            story.append(Paragraph(f"• {line[2:]}", bullet_style))
        elif "```" in line:
            continue  # skipping code block markers for now
        else:
            story.append(Paragraph(line, body_style))

        story.append(Spacer(1, 10))

    doc.build(story)
