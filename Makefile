build:
	mvn clean package

deploy: build
	sam deploy --guided
