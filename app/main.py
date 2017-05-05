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
