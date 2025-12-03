# Etapa 1: Build
FROM debian:bookworm-slim AS build

ENV LANG=en_US.utf8
ENV NOTVISIBLE="in users profile"
ENV ASTERISK_VERSION=20.17.0
ENV ASTERISK_AUDIO_PROMPTS_EN=https://downloads.asterisk.org/pub/telephony/sounds/asterisk-core-sounds-en-wav-current.tar.gz
ENV ASTERISK_AUDIO_PROMPTS_ES=https://downloads.asterisk.org/pub/telephony/sounds/asterisk-core-sounds-es-wav-current.tar.gz
ENV OMNILEADS_AUDIO_PROMPTS=https://omnileads.sfo3.digitaloceanspaces.com/asterisk-oml-sounds-current.tar.gz
ENV OMNILEADS_MOH=https://fts-public-packages.s3-sa-east-1.amazonaws.com/asterisk/asterisk-oml-moh-current.tar.gz

# Instalar herramientas de compilación y dependencias
RUN apt update -qq && \
    apt install -y --no-install-recommends \
      autoconf automake build-essential \
      binutils-dev libpopt-dev libcurl4-openssl-dev \
      libedit-dev libgsm1 libgsm1-dev libogg-dev libresample1-dev \
      libspandsp-dev libspeex-dev libspeexdsp-dev \
      libsqlite3-dev libsrtp2-dev libssl-dev libvorbis-dev \
      libxml2-dev libxslt1-dev portaudio19-dev procps subversion \
      uuid-dev xmlstarlet libjansson-dev curl wget ca-certificates \
      sox git lame && \
    rm -rf /var/lib/apt/lists/*

# Clonar y compilar Asterisk
RUN mkdir -p /usr/src/asterisk && \
    git clone --branch ${ASTERISK_VERSION} https://github.com/asterisk/asterisk.git /usr/src/asterisk && \
    cd /usr/src/asterisk && \
    contrib/scripts/get_mp3_source.sh && \
    ./configure --with-resample --with-pjproject-bundled --with-jansson-bundled && \
    make menuselect/menuselect menuselect-tree menuselect.makeopts && \
    menuselect/menuselect --disable BUILD_NATIVE menuselect.makeopts && \
    menuselect/menuselect --enable BETTER_BACKTRACES menuselect.makeopts && \
    menuselect/menuselect --enable codec_gsm menuselect.makeopts && \
    menuselect/menuselect --enable codec_opus menuselect.makeopts && \
    menuselect/menuselect --disable-category MENUSELECT_CORE_SOUNDS menuselect.makeopts && \
    menuselect/menuselect --disable-category MENUSELECT_MOH menuselect.makeopts && \
    menuselect/menuselect --disable-category MENUSELECT_EXTRA_SOUNDS menuselect.makeopts && \
    make -j$(nproc) && \
    make install && \
    make samples && \
    rm -rf /usr/src/asterisk

# Install codec g729
RUN wget http://asterisk.hosting.lv/bin/codec_g729-ast200-gcc4-glibc-x86_64-pentium4.so && \
    mv codec_g729* /usr/lib/asterisk/modules/codec_g729.so && \
    chmod +x /usr/lib/asterisk/modules/codec_g729.so

# Descargar sonidos
RUN mkdir -p /var/lib/asterisk/sounds/oml /var/lib/asterisk/sounds/en /var/lib/asterisk/sounds/es /var/lib/asterisk/sounds/oml /var/lib/asterisk/moh && \
    wget -q $ASTERISK_AUDIO_PROMPTS_EN -O - | tar xzv -C /var/lib/asterisk/sounds/en || true && \
    wget -q $ASTERISK_AUDIO_PROMPTS_ES -O - | tar xzv -C /var/lib/asterisk/sounds/es || true && \
    wget -q $OMNILEADS_AUDIO_PROMPTS -O - | tar xzv -C /var/lib/asterisk/sounds/oml || true && \
    wget -q $OMNILEADS_MOH -O - | tar xzv -C /var/lib/asterisk/moh || true

# Limpiar herramientas de compilación
RUN apt remove --purge -y git build-essential && \
    apt autoremove -y && \
    apt clean && \
    rm -rf /var/lib/apt/lists/* /usr/include/asterisk

# Etapa 2: Runtime
FROM python:3.10-slim-bookworm AS run

ENV LANG=en_US.utf8
ENV NOTVISIBLE="in users profile"

# Instalar dependencias de ejecución mínimas
RUN apt update -qq && \
    apt install -y --no-install-recommends \
      binutils libicu-dev && \
    apt autoremove -y && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*

# Copiar binarios y configuraciones de Asterisk desde la etapa de compilación
COPY --from=build /usr/local /usr/local
COPY --from=build /usr/lib/libasterisk* /usr/lib/
COPY --from=build /etc/asterisk /etc/asterisk/
COPY --from=build /var/lib/asterisk /var/lib/asterisk
COPY --from=build /var/log/asterisk /var/log/asterisk
COPY --from=build /var/spool/asterisk /var/spool/asterisk
COPY --from=build /usr/lib/asterisk /usr/lib/asterisk/
COPY --from=build /var/run/asterisk/ /var/run/asterisk/
COPY --from=build /usr/sbin/ast* /usr/sbin/

COPY --from=build /usr/lib/x86_64-linux-gnu/libsqlite3.so.0 /usr/lib/x86_64-linux-gnu/libsqlite3.so.0
COPY --from=build /usr/lib/x86_64-linux-gnu/libxml2.so.2 /usr/lib/x86_64-linux-gnu/libxml2.so.2
COPY --from=build /usr/lib/x86_64-linux-gnu/libxslt.so.1 /usr/lib/x86_64-linux-gnu/libxslt.so.1
COPY --from=build /usr/lib/x86_64-linux-gnu/libssl.so.3 /usr/lib/x86_64-linux-gnu/libssl.so.3
COPY --from=build /usr/lib/x86_64-linux-gnu/libcrypto.so.3 /usr/lib/x86_64-linux-gnu/libcrypto.so.3
COPY --from=build /usr/lib/x86_64-linux-gnu/libedit.so.2 /usr/lib/x86_64-linux-gnu/libedit.so.2
COPY --from=build /usr/lib/x86_64-linux-gnu/libbsd.so.0 /usr/lib/x86_64-linux-gnu/libbsd.so.0
COPY --from=build /usr/lib/x86_64-linux-gnu/libcurl.so.4 /usr/lib/x86_64-linux-gnu/libcurl.so.4

COPY ./modules.conf /etc/asterisk/modules.conf

# Configuración de permisos
RUN chmod -R 750 /var/lib/asterisk /var/spool/asterisk /var/log/asterisk && \
    useradd -r -s /bin/false asterisk && \
    chown -R asterisk:asterisk /var/lib/asterisk /var/spool/asterisk /var/log/asterisk
