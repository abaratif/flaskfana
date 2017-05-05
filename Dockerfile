FROM tiangolo/uwsgi-nginx-flask:flask

# COPY requirements.txt requirements.txt
# RUN pip install -r requirements.txt

COPY ./app /app