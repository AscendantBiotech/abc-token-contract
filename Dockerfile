FROM nikolaik/python-nodejs:python3.6-nodejs12

WORKDIR /usr/src

RUN pip install pipenv
RUN npm install -g truffle --unsafe-perm
RUN npm install -g solc --unsafe-perm

COPY / /usr/src
RUN pipenv install --dev


