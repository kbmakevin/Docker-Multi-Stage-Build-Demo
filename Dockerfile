#
# ---- Base Stage ----
FROM alpine:3.9.3 AS base
# install node
RUN apk add --no-cache nodejs-current npm tini
# Create a group and user
RUN addgroup -S node && adduser -S node -G node
USER node
# set working directory
RUN mkdir -p /home/node/app
RUN chown node:node /home/node/app
WORKDIR /home/node/app
# Set tini as entrypoint
ENTRYPOINT ["/sbin/tini", "--"]
# copy project file
COPY src/package.json .

#
# ---- Deps ----
FROM base AS dependencies
# Need to bypass self-signed cert error when on corp network
RUN npm config set strict-ssl false
RUN npm install --only=production
# copy production node_modules aside
RUN cp -R node_modules prod_node_modules
# install ALL node_modules, including "devDependencies"
RUN npm install

#
# ---- Release ----
FROM base AS release
ENV PORT=3000
# copy production node_modules
COPY --from=dependencies /home/node/app/prod_node_modules ./node_modules

HEALTHCHECK --interval=5s \
						--timeout=5s \
						--retries=6 \
						CMD curl -fs http://localhost:$PORT/ || exit 1

CMD ["npm", "run", "start:prod"]

#
# ---- Develop ----
FROM base AS develop
# copy node_modules
COPY --from=dependencies /home/node/app/node_modules ./node_modules
CMD ["npm", "run", "start"]
