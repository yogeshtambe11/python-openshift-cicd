FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /opt/app

COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ .

EXPOSE 8080

# OpenShift's restricted SCC can assign an arbitrary non-root UID.
# Application files are readable by that UID.
RUN chmod -R a+rX /opt/app

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "app:app"]
