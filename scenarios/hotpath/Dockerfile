FROM python:3.11-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends curl procps \
 && rm -rf /var/lib/apt/lists/* \
 && pip install --no-cache-dir py-spy

WORKDIR /app
COPY app/ /app/
