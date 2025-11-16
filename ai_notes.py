# ai_notes.py
from openai import OpenAI
import os

import os
from dotenv import load_dotenv
from openai import OpenAI

load_dotenv()  # load the .env file

api_key = os.getenv("OPENAI_API_KEY")
print("API KEY FOUND:", api_key is not None)  # Debug line

client = OpenAI(api_key=api_key)


client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))

def generate_notes(topic: str) -> str:
    prompt = f"""
    Generate detailed student-friendly study notes on "{topic}".
    The output should cover approximately 10 A4 pages worth of content.

    Follow this structure:
    - Main Headings
    - Subheadings
    - Bullet points
    - Definitions
    - Important concepts
    - Examples
    - Summary at the end

    Make it crisp, easy to revise, and well-organized.
    """

    response = client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[
            {"role": "user", "content": prompt}
        ]
    )

    return response.choices[0].message.content
