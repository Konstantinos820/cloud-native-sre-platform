# -----------------
# 1. BUILD STAGE
# -----------------
FROM python:3.12.16-slim-bullseye AS builder

WORKDIR /app

# Εγκατάσταση απαραίτητων εργαλείων και αναβάθμιση συστήματος για ασφάλεια
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends gcc build-essential && \
    rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# -----------------
# 2. RUNTIME STAGE
# -----------------
FROM python:3.12.16-slim-bullseye

WORKDIR /app

# Αναβάθμιση πακέτων ασφαλείας και στο τελικό image
RUN apt-get update && apt-get upgrade -y && \
    rm -rf /var/lib/apt/lists/*

# Αντιγραφή των εγκατεστημένων βιβλιοθηκών από το build stage
COPY --from=builder /root/.local /root/.local
COPY src/ /app/src/

ENV PATH=/root/.local/bin:$PATH
ENV PORT=8000

EXPOSE 8000

CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000"]