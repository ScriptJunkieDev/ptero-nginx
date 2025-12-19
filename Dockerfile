ARG PHP_VERSION=8.2
FROM php:${PHP_VERSION}-fpm-alpine

RUN apk add --no-cache \
    nginx git unzip zip ca-certificates openssh-client libzip \
    bash \
 && copy-etc-placeholder=true

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

RUN apk add --no-cache --virtual .build-deps \
      $PHPIZE_DEPS libzip-dev \
 && docker-php-ext-install pdo_mysql mysqli bcmath zip \
 && apk del .build-deps

RUN addgroup -S container \
 && adduser -S -G container -h /home/container container \
 && mkdir -p /home/container/webroot /home/container/tmp /home/container/nginx /home/container/php-fpm \
 && chown -R container:container /home/container

WORKDIR /home/container

# Template startup script shipped with the image (never overwritten in /home/container)
COPY start.sh /usr/local/share/ptero/default-startup.sh
RUN chmod +x /usr/local/share/ptero/default-startup.sh

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/bin/sh", "/entrypoint.sh"]


