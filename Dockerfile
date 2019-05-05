#
# ---- Base Stage ----
FROM alpine:3.9.3 AS node-base

LABEL MAINTAINER="Kevin Ma <kbma.kevin@gmail.com>"

USER root

# Create a group and user for node
RUN apk add --no-cache shadow sudo \
		&& addgroup -S node \
		&& adduser -S node -G node -s /bin/sh \
		&& echo "node ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/node \
		&& chmod 0440 /etc/sudoers.d/node

# install node
RUN apk add --no-cache nodejs-current npm tini

# set working directory
RUN mkdir -p /home/node/app
RUN chown node:node /home/node/app
WORKDIR /home/node/app

# create directories for java
RUN mkdir -p /opt/java \
		&& chown node:node /opt/java

USER node

# Set tini as entrypoint
ENTRYPOINT ["/sbin/tini", "--"]

# copy project file
COPY src/package.json .

#
# ---- Node Base with Java Deps ----
FROM node-base AS node-base-with-java-deps

# temporarily restore root access to install java
USER root

# install dependencies for java
RUN apk add --no-cache --virtual .build-deps curl binutils \
    && GLIBC_VER="2.29-r0" \
    && ALPINE_GLIBC_REPO="https://github.com/sgerrand/alpine-pkg-glibc/releases/download" \
    && GCC_LIBS_URL="https://archive.archlinux.org/packages/g/gcc-libs/gcc-libs-8.2.1%2B20180831-1-x86_64.pkg.tar.xz" \
    && GCC_LIBS_SHA256=e4b39fb1f5957c5aab5c2ce0c46e03d30426f3b94b9992b009d417ff2d56af4d \
    && ZLIB_URL="https://archive.archlinux.org/packages/z/zlib/zlib-1%3A1.2.11-3-x86_64.pkg.tar.xz" \
    && ZLIB_SHA256=17aede0b9f8baa789c5aa3f358fbf8c68a5f1228c5e6cba1a5dd34102ef4d4e5 \
    && curl -Ls https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub -o /etc/apk/keys/sgerrand.rsa.pub \
    && SGERRAND_RSA_SHA256="823b54589c93b02497f1ba4dc622eaef9c813e6b0f0ebbb2f771e32adf9f4ef2" \
    && echo "${SGERRAND_RSA_SHA256}  /etc/apk/keys/sgerrand.rsa.pub" | sha256sum -c - \
    && curl -Ls ${ALPINE_GLIBC_REPO}/${GLIBC_VER}/glibc-${GLIBC_VER}.apk > /tmp/${GLIBC_VER}.apk \
    && apk add /tmp/${GLIBC_VER}.apk \
    && curl -Ls ${GCC_LIBS_URL} -o /tmp/gcc-libs.tar.xz \
    && echo "${GCC_LIBS_SHA256}  /tmp/gcc-libs.tar.xz" | sha256sum -c - \
    && mkdir /tmp/gcc \
    && tar -xf /tmp/gcc-libs.tar.xz -C /tmp/gcc \
    && mv /tmp/gcc/usr/lib/libgcc* /tmp/gcc/usr/lib/libstdc++* /usr/glibc-compat/lib \
    && strip /usr/glibc-compat/lib/libgcc_s.so.* /usr/glibc-compat/lib/libstdc++.so* \
    && curl -Ls ${ZLIB_URL} -o /tmp/libz.tar.xz \
    && echo "${ZLIB_SHA256}  /tmp/libz.tar.xz" | sha256sum -c - \
    && mkdir /tmp/libz \
    && tar -xf /tmp/libz.tar.xz -C /tmp/libz \
    && mv /tmp/libz/usr/lib/libz.so* /usr/glibc-compat/lib \
    && apk del --purge .build-deps \
    && rm -rf /tmp/${GLIBC_VER}.apk /tmp/gcc /tmp/gcc-libs.tar.xz /tmp/libz /tmp/libz.tar.xz /var/cache/apk/*

#
# ---- Node JDK 11 Base ----
FROM node-base-with-java-deps AS node-jdk11

# install Java11 LTS JDK
ADD https://github.com/AdoptOpenJDK/openjdk11-binaries/releases/download/jdk-11.0.3%2B7/OpenJDK11U-jdk_x64_linux_hotspot_11.0.3_7.tar.gz /opt/java
RUN echo "Added tar ball to /opt/java..."
RUN cd /opt/java \
		&& JAVA_TAR="/opt/java/OpenJDK11U-jdk_x64_linux_hotspot_11.0.3_7.tar.gz" \
		&& tar -xf $JAVA_TAR \
		&& ln -s /opt/java/jdk-11.0.3+7 /opt/java/current \
		&& rm -rf $JAVA_TAR

ENV JAVA_HOME=/opt/java/current
ENV PATH="$JAVA_HOME/bin:$PATH"

# revert back to node user
USER node

#
# ---- Node JRE 11 Base ----
FROM node-base-with-java-deps AS node-jre11

# temporarily restore root access to install java
USER root

# install Java11 LTS JRE
ADD https://github.com/AdoptOpenJDK/openjdk11-binaries/releases/download/jdk-11.0.3%2B7/OpenJDK11U-jre_x64_linux_hotspot_11.0.3_7.tar.gz /opt/java
RUN echo "Added tar ball to /opt/java..."
RUN cd /opt/java \
		&& JAVA_TAR="/opt/java/OpenJDK11U-jre_x64_linux_hotspot_11.0.3_7.tar.gz" \
		&& tar -xf $JAVA_TAR \
		&& ln -s /opt/java/jdk-11.0.3+7-jre /opt/java/current \
		&& rm -rf $JAVA_TAR

# revert back to node user
USER node
#
# ---- Node Deps ----
FROM node-base AS node-dependencies

# Need to bypass self-signed cert error when on corp network
RUN npm config set strict-ssl false
RUN npm install --only=production

# copy production node_modules aside
RUN cp -R node_modules prod_node_modules

# install ALL node_modules, including "devDependencies"
RUN npm install

#
# ---- Release ----
FROM node-jre11 AS release
ENV PORT=3000

# copy production node_modules
COPY --from=node-dependencies /home/node/app/prod_node_modules ./node_modules

# run healthcheck for the node app
HEALTHCHECK --interval=5s \
						--timeout=5s \
						--retries=6 \
						CMD curl -fs http://localhost:$PORT/ || exit 1

CMD ["npm", "run", "start:prod"]

#
# ---- Develop ----
FROM node-jdk11 AS develop

# copy node_modules
COPY --from=node-dependencies /home/node/app/node_modules ./node_modules

RUN echo "testing java as $(whoami)...." \
		&& echo "JAVA_HOME=$JAVA_HOME" \
		&& ls -l $JAVA_HOME/ \
		&& echo "PATH=$PATH" \
		&& ls -l $JAVA_HOME/bin/ \
		&& which java \
		&& java -version

CMD ["npm", "run", "start"]
