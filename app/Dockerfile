# -----------------
# 1. BUILD STAGE
# -----------------
FROM python:3.12.18-slim-bookworm AS builder

WORKDIR /app

# Εγκατάσταση απαραίτητων εργαλείων και αναβάθμιση συστήματος για ασφάλεια
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends gcc build-essential ca-certificates && \
    rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
# Install Python dependencies into /usr/local so they can be copied to the final image
RUN pip install --no-cache-dir --prefix=/usr/local -r requirements.txt

# Remove build tools to keep the builder clean and reduce attack surface
RUN apt-get purge -y --auto-remove gcc build-essential && rm -rf /var/lib/apt/lists/*

# -----------------
# 2. RUNTIME STAGE
# -----------------
FROM python:3.12.18-slim-bookworm

WORKDIR /app

# Εγκατάσταση μόνο των απαραίτητων runtime πακέτων (π.χ. πιστοποιητικά)
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Αντιγραφή των εγκατεστημένων βιβλιοθηκών από το build stage
COPY --from=builder /usr/local /usr/local
COPY src/ /app/src/

ENV PATH=/usr/local/bin:$PATH
ENV PORT=8000

EXPOSE 8000

CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000"]