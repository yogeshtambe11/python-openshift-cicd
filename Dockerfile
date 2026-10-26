FROM registry.access.redhat.com/ubi9/python-39:latest

WORKDIR /app
COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ /app/

EXPOSE 8080
USER 1001

CMD ["python", "app.py"]
