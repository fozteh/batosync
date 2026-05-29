FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .
COPY templates/ templates/

# Saves are stored here — mount a volume to persist them
VOLUME ["/data/saves"]

EXPOSE 5000

ENV SAVES_DIR=/data/saves \
    MAX_BACKUPS=3 \
    API_KEY=""

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--timeout", "120", "app:app"]
