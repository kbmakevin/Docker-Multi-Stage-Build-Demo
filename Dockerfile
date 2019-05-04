FROM node:12-slim AS builder

#COPY . /src
RUN mkdir /src
COPY src/package.json /src
WORKDIR /src

# Need to bypass self-signed cert error when on corp network
RUN npm config set strict-ssl false
RUN npm install

FROM node:12-slim as final

ENV PORT=3000
#EXPOSE $PORT

WORKDIR /home/node/app

COPY --from=builder /src/node_modules node_modules

HEALTHCHECK --interval=5s \
						--timeout=5s \
						--retries=6 \
						CMD curl -fs http://localhost:$PORT/ || exit 1

USER node

CMD ["npm", "run", "start:prod"]

FROM node:12-slim as develop

#ENV PORT=3000
#EXPOSE $PORT

WORKDIR /home/node/app

COPY --from=builder /src/node_modules node_modules

# Need to bypass self-signed cert error when on corp network
RUN npm config set strict-ssl false
RUN npm install --save nodemon

USER node

CMD ["npm", "run", "start"]
