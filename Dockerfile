FROM tiangolo/uwsgi-nginx-flask:flask

# COPY requirements.txt requirements.txt
# RUN pip install -r requirements.txt

# Install telegraf
RUN apt-get update
RUN wget https://dl.influxdata.com/telegraf/releases/telegraf_1.0.0_amd64.deb
RUN dpkg -i telegraf_1.0.0_amd64.deb
# Custom config
COPY telegraf.conf /etc/telegraf/telegraf.conf


# Make the wusgi log
RUN mkdir /var/log/uwsgi
RUN touch /var/log/uwsgi/uwsgi.log

# Custom Supervisord config
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Copy over files
COPY ./app /app
RUN chmod -R 777 . 