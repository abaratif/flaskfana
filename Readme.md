# Flask + Grafana = Flaskfana

#### Resources
1. [Tiangolo's uwsgi-nginx-flask docker image](https://hub.docker.com/r/tiangolo/uwsgi-nginx/)
2. [InfluxDBs guide to parsing logfiles with Telegraf](https://hub.docker.com/r/tiangolo/uwsgi-nginx/)
3. [Brian Christner's Docker Monitoring guide](https://github.com/vegasbrianc/docker-monitoring)
4. [Grok Debugger](https://grokdebug.herokuapp.com/)
5. [Telegraf grok patterns](https://github.com/influxdata/telegraf/blob/master/plugins/inputs/logparser/grok/patterns/influx-patterns)

## A simple Flask app

Let's start with a simple example Flask app. Here's the code:

#### ~/app/main.py
```
from flask import Flask
import time

app = Flask(__name__)

@app.route('/')
def index():
	return "Hello World!"


@app.route('/api/obj/<int:id_num>')
def get_by_id(id_num):
	if id_num % 2 == 0:
		time.sleep(5)		
	elif id_num % 2 == 1:
		time.sleep(1)

	return "Fetched result"

if __name__ == "__main__":
	app.run(host='0.0.0.0', debug=True, port=80)	
```

We've got a home route that gives us Hello World, and an api route, which takes in an object id and returns "Fetched Result". Noticed that we've made a wait of 5 seconds for even numbered IDs, and a wait of 1 second for odd numbered IDs. This example will help us visualize differing response times once we get our monitoring infrastructure set up.

## The Docker image

Now we need to deploy this simple app to Docker. In order to keep things simple, we're going to use [a Docker image](https://hub.docker.com/r/tiangolo/uwsgi-nginx/ ) that is already preconfigured to properly deploy Flask apps. It includes nginx and wusgi, which together will give us a solid architecture for handling production requests. All we need to do is drop in our main.py file, and the image takes care of the rest. Thus, our Dockerfile just needs to include this image, and copy over our app code. 

#### ~/Dockerfile
```
FROM tiangolo/uwsgi-nginx-flask:flask

# COPY requirements.txt requirements.txt
# RUN pip install -r requirements.txt

COPY ./app /app
```
Note that the two lines related to installing pip packages are commented out. This simple application won't need them, since it only uses Flask, which will be installed by the image along with nginx and wusgi. However, most applications will probably include more packages, and so will need to install using pip.

Let's build the image
 ``` docker build -t flaskfana_image .``` 
and then run it
 ``` docker run -d --name flaskfana_container -p 80:80 flaskfana_image ```

Executing ``` docker ps ``` should give us some information showing the container is up and running. Before we actually start hitting our application with requests, let's watch the log files to see what kind of information we get. This image is configured so that nginx and wusgi logs are piped to stdout, which means that you can easily view them by using the ```docker logs``` command. 

Let's run ``` docker logs -f flaskfana_container``` and then hit our app with a few requests to the home route.  We should get somethign like the following:

```
10.0.2.2 - - [05/May/2017:14:47:36 +0000] "GET / HTTP/1.1" 200 12 "-" "Mozilla/5.0 (Windows NT 6.1; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/57.0.2987.133 Safari/537.36" "-"
[pid: 13|app: 0|req: 1/1] 10.0.2.2 () {40 vars in 650 bytes} [Fri May  5 14:47:36 2017] GET / => generated 12 bytes in 2 msecs (HTTP/1.1 200) 2 headers in 79 bytes (1 switches on core 0)
[pid: 13|app: 0|req: 2/2] 10.0.2.2 () {40 vars in 672 bytes} [Fri May  5 14:51:39 2017] GET /api/obj/124 => generated 14 bytes in 5005 msecs (HTTP/1.1 200) 2 headers in 79 bytes (1 switches on core 0)
10.0.2.2 - - [05/May/2017:14:51:44 +0000] "GET /api/obj/124 HTTP/1.1" 200 14 "-" "Mozilla/5.0 (Windows NT 6.1; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/57.0.2987.133 Safari/537.36" "-"
10.0.2.2 - - [05/May/2017:14:51:52 +0000] "GET /api/obj/123 HTTP/1.1" 200 14 "-" "Mozilla/5.0 (Windows NT 6.1; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/57.0.2987.133 Safari/537.36" "-"
[pid: 13|app: 0|req: 3/3] 10.0.2.2 () {40 vars in 672 bytes} [Fri May  5 14:51:51 2017] GET /api/obj/123 => generated 14 bytes in 1002 msecs (HTTP/1.1 200) 2 headers in 79 bytes (1 switches on core 0)

```

The very last line is from uwsgi, and is interesting because it shows us what type of request was handled (a GET in this case), at what endpoint it occurred (/api/obj/123) and how long it took to process (1002 msecs). Wouldn't it be nice if we could collect all of this data so that as our application grows, we can write queries to analyze response times across different endpoints? This is where our monitoring stack comes in!

## InfluxDB
### Background

InfluxDB will hold all the data we parse from our logs, and will store it in a time series format. Later, our dashboarding frontend, Grafana, will connect to this database and allow us to easily view data. That's about all we need to know about it for now, so let's go ahead and set it up!
### Setup
We want to run InfluxDB in it's own Docker container, which will be easy since a prebuilt version already exists. All we need to do is run the image and pass in some configuration options.

```
docker run -p 8083:8083 -p 8086:8086 \
--expose 8090 --expose 8099 \
-v influxdb:/var/lib/influxdb \
-e PRE_CREATE_DB=telegraf \
--name influxdb \
 influxdb:0.13
```
This will start an InfluxDB container and create a database named telegraf. It will also map the necessary ports, which will come in handy later once we want to link the rest of our monitoring stack to this DB instance. To double check that everything worked OK, head over to http://localhost:8083/. You should see the InfluxDB console. Now that we've got a database, let's fill it with some data!

## Collecting log data with Telegraf

### Telegraf and the logparser plugin
Telegraf is the part of our monitoring stack that sits closest to our application (or more specifically, our log files) in that it parses our log files and then passes them on to InfluxDB for storage as time series data points. Telegraf has the benefit of being lightweight and easy to configure, and it's logparser plugin includes many rules to parse common log file styles, such as the Combined Log Format, which is used by nginx. Unfortunately for us, there isn't a builtin logparser rule for the format used by uwsgi logs, which means we will have to write our own. Fortunately, I've already written a suitable pattern and will provide it here. However, if you are interested in learning more, I'd recommend checking out [this guide](https://hub.docker.com/r/tiangolo/uwsgi-nginx/) from InfluxData which covers setting up telegraf, as well as writing custom logparser plugins.

### Telegraf config

I'll present a simplifed example of a telegraf config file, and explain important parts. Then I'll present the version that we will use in our application, which will include the parsing of the uwsgi log file.

#### ~/telegraf.conf.old (example)
```
[[inputs.logparser]]
  ## files to tail.
  files = ["/var/log/nginx/access.log"]
  ## Read file from beginning.
  from_beginning = true
  ## Override the default measurement name, which would be "logparser_grok"
  name_override = "nginx_access_log"
  ## For parsing logstash-style "grok" patterns:
  [inputs.logparser.grok]
    patterns = ["%{COMBINED_LOG_FORMAT}"]

[[outputs.influxdb]]
  ## The full HTTP or UDP endpoint URL for your InfluxDB instance.
  urls = ["http://localhost:8086"] # required
  ## The target database for metrics (telegraf will create it if not exists).
  database = "telegraf" # required
  ## Write timeout (for the InfluxDB client), formatted as a string.
  timeout = "5s"
```

The first part of this file tells us what to read and how to read it. Specifically, we have a path to the location of the log file. The name_override will come into play once telegraf writes the data into InfluxDB, but isn't of much importance at the moment. The grok pattern used here is the thing we are most focused on. This simple example uses the combined log format we talked about before.

The second part of the config file tells telegraf where to write data. The data will be written to a database named telegraf, which will reside on an InfluxDB instance on port 8086. These settings will be left unchanged for our purposes. Now let's look at the config file we will actually be using, and discuss the changes.

#### ~/telegraf.conf (actual)
```
[[inputs.logparser]]
  ## file(s) to tail:
  files = ["/var/log/uwsgi/uwsgi.log"]
  from_beginning = true
  name_override = "uwsgi_log"
  ## For parsing logstash-style "grok" patterns:
  [inputs.logparser.grok]
    patterns = ["%{UWSGI_LOG}"]
    custom_patterns = '''
       UWSGI_LOG \[pid: %{NUMBER:pid:int}\|app: %{NUMBER:id:int}\|req: %{NUMBER:currentReq:int}/%{NUMBER:totalReq:int}\] %{IP:remoteAddr} \(%{WORD:remoteUser}?\) \{%{NUMBER:CGIVar:int} vars in %{NUMBER:CGISize:int} bytes\} %{GREEDYDATA:timestamp} %{WORD:method:tag} %{URIPATHPARAM:uri:tag} \=\> generated %{NUMBER:resSize:int} bytes in %{NUMBER:resTime:int} msecs \(HTTP/%{NUMBER:httpVer:float} %{NUMBER:status:int}\) %{NUMBER:headers:int} headers in %{NUMBER:headersSize:int} bytes %{GREEDYDATA:coreInfo}
    '''
[[outputs.influxdb]]
  ## The full HTTP or UDP endpoint URL for your InfluxDB instance.
  urls = ["http://influxsrv:8086"] # This connection shall be accomplished through container linking
  ## The target database for metrics (telegraf will create it if not exists).
  database = "telegraf" # required
  ## Write timeout (for the InfluxDB client), formatted as a string.
  timeout = "5s"
```
A few things have changed here, most notably the grok pattern. Let's discuss the way a grok pattern works.

### Grok patterns
A grok pattern is a regex like expression that tells telegraf what data to extract logfile during parsing. Let's take an example and break down the components.

This portion of the config
```
generated %{NUMBER:resSize:int} bytes in %{NUMBER:resTime} msecs
```
Is designed to read this portion of the log
```
generated 14 bytes in 1002 msecs 
```
This portion consists of two grok patterns. The *generated*, *bytes in*, and *msecs* are not part of any grok pattern, and so will not be parsed. The first grok pattern is setup to read the size of the request. A grok pattern is written as 

```
`%{<capture_syntax>[:<semantic_name>][:<modifier>]}`
```
The first grok pattern ``` %{NUMBER:resSize:int} ``` uses the NUMBER pattern to parse data, and assigns it to the resSize field (the second part of our pattern). The captured data is then cast to an int, according to the third part of our pattern.

Let's check out one more of our grok patterns.
```
%{URIPATHPARAM:uri:tag}
```
This pattern uses the URIPATHPARAM pattern to parse in a URI path, and then stores it as a variable called uri. The tag modifier will make sure that this field is stored in InfluxDB as a tag, rather than a field, so that we can use it to filter queries later on during our analysis.

### Telegraf installation

Now that we have our telegraf config all sorted out, let's have our Docker image install telegraf and copy over our custom config. This will involve changes to our Dockerfile, as well as changes to the config file of the Supervisor process control system used by our image. We will also need to do a few more tweaks to make telegraf work properly. Our modified Dockerfile and our new supervisord.conf are below.

#### ~/Dockerfile
```
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
```

####  ~/supervisord.conf
```
[supervisord]
nodaemon=true

[program:uwsgi]
command=/usr/local/bin/uwsgi --ini /etc/uwsgi/uwsgi.ini --ini /app/uwsgi.ini

[program:telegraf]
command=/usr/bin/telegraf

[program:nginx]
command=/usr/sbin/nginx
stdout_logfile=/var/log/nginx/access.log
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
```
If you recall, the base nginx-uwsgi-flask image redirected log output to /dev/stdout so that we could see it using the ```docker logs``` command. However, now that we will be collecting log data, we want it to be written to a file. We can do this by specifying a line in uwsgi's config file. Therefore, we need to modify the supervisord.conf file to read a custom uwsgi config file. We also included a line to start telegraf alongside the rest of our other services. Our short custom uwsgi file is below:

####~/app/uwsgi.ini
```
[uwsgi]
module = main
callable = app

logto =/var/log/uwsgi/uwsgi.log
```
Alright, lets build and run our image again and see if our log data gets collected and stored in InfluxDB. Remember, your InfluxDB instance should already be up at this point.

Let's build the image as we did before
 ``` docker build -t flaskfana_image . ``` 
and then run it, this time linking our InfluxDB container
 ``` docker run -p 80:80 -p 8125:8125 -t -d --link=influxdb:influxsrv --name flaskfana_container  flaskfana_image ```

Navigate to http://localhost and execute a few requests on your server. Now head to your InfluxDB console at http://localhost:8083 and switch the database to telegraf using the dropdown in the top right. Execute the following query: 
```
SELECT * FROM uwsgi_log
```

You should see a few lines of data, meaning that our log files were successfully parsed. Great! We are now ready to start visualizing this data using Grafana.

## Visualization with Grafana

### Installation
Grafana installation is straightforward thanks to a prebuilt image, much like InfluxDB installation. The docker command is as follows:

```
docker run -d -p 3000:3000 \
-e HTTP_USER=admin \
-e HTTP_PASS=admin \
-e INFLUXDB_HOST=influxsrv \
-e INFLUXDB_PORT=8086 \
-e INFLUXDB_NAME=telegraf \
-e INFLUXDB_USER=root \
-e INFLUXDB_PASS=root \
--link=influxdb:influxsrv  \
--name grafana \
grafana/grafana:4.2.0
```
Once again, we are linking containers in order to easily connect to InfluxDB. Also note that we have specified a number of configuration options, including the name of the database we want to read from in InfluxDB. We can change this from within Grafana if we so choose. Head over to http://localhost:3000 and log in using the credentials.

### Configuration
#### Adding a data source
We need to tell Grafana that we want to read from an InfluxDB data source. The first step is to add this data source, so click on that button on the homepage. Name the data source telegraf, and choose the type as InfluxDB. The URL is http://influxsrv:8086 as per our container link. Fill in the InfluxDB details, with telegraf as the database, and root:root as user:pass.
#### A first dashboard
The best exercise to ensure that everything is working is to set up a simple dashboard based on the query we used earlier. From Grafana's homepage, head to Dashboards > New, and choose the table type. Now hit edit, and go down to the query field. Use the toggle on the right to get the manual edit mode, and input the same query as before, ``` SELECT * FROM uwsgi_log ```. You should now see the same datapoints you saw when you ran the query beforehand in the InfluxDB console. Congratulations! You've mastered the whole pipeline of collecting, storing, and viewing data. Now comes the fun of customizing your dashboards.

### Building a dashboard
