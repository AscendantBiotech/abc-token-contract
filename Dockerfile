FROM nikolaik/python-nodejs:python3.7-nodejs12

RUN apt-get update && apt-get install make

WORKDIR /usr/src

RUN pip install pipenv
RUN npm install -g truffle --unsafe-perm
RUN npm install -g solc --unsafe-perm

RUN git config --global user.email "you@example.com"

RUN pipenv run git clone https://github.com/vyperlang/vyper.git && \
    cd vyper && \
    git checkout tags/v0.1.0-beta.17 && \
    git fetch origin pull/1848/head:privatefuncs && \
    git merge privatefuncs && \
    make


COPY / /usr/src
RUN pipenv install --dev
RUN pip list -v

