FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      bash git ca-certificates openssh-client rsync \
      tar gzip xz fonts-dejavu \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

WORKDIR /opt/eculibre
COPY tools/mapviz.py /opt/eculibre/mapviz.py
RUN chmod +x /opt/eculibre/mapviz.py

WORKDIR /workspace