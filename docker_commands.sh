## InfluxDB

# docker run -p 8083:8083 -p 8086:8086 \
# --expose 8090 --expose 8099 \
# -v influxdb:/var/lib/influxdb \
# -e PRE_CREATE_DB=telegraf \
# --name influxdb \
#  influxdb:0.13