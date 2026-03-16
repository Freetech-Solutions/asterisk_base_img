# Etapa 1: Build
FROM debian:trixie-slim AS build

# Argumento automático de Docker para detectar arquitectura (amd64 o arm64)
ARG TARGETARCH

ENV LANG=en_US.utf8
ENV ASTERISK_VERSION=22.8.2
ENV ASTERISK_AUDIO_PROMPTS_EN=https://downloads.asterisk.org/pub/telephony/sounds/asterisk-core-sounds-en-wav-current.tar.gz
ENV ASTERISK_AUDIO_PROMPTS_ES=https://downloads.asterisk.org/pub/telephony/sounds/asterisk-core-sounds-es-wav-current.tar.gz
ENV OMNILEADS_AUDIO_PROMPTS=https://omnileads.sfo3.digitaloceanspaces.com/asterisk-oml-sounds-current.tar.gz
ENV OMNILEADS_MOH=https://fts-public-packages.s3-sa-east-1.amazonaws.com/asterisk/asterisk-oml-moh-current.tar.gz

RUN apt update -qq && \
    apt install -y --no-install-recommends \
      autoconf automake build-essential \
      binutils-dev libpopt-dev libcurl4-openssl-dev \
      libedit-dev libgsm1 libgsm1-dev libogg-dev libresample1-dev \
      libspandsp-dev libspeex-dev libspeexdsp-dev \
      libsqlite3-dev libsrtp2-dev libssl-dev libvorbis-dev \
      libxml2-dev libxslt1-dev portaudio19-dev procps subversion \
      uuid-dev xmlstarlet libjansson-dev curl wget ca-certificates \
      sox git lame \
      ### AÑADIDO PARA ARA/ODBC (Dependencias de compilación) ### \
      unixodbc-dev libpq-dev odbc-postgresql && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /usr/src/asterisk && \
    git clone --branch ${ASTERISK_VERSION} https://github.com/asterisk/asterisk.git /usr/src/asterisk && \
    cd /usr/src/asterisk && \
    contrib/scripts/get_mp3_source.sh && \
    # build_native deshabilitado es crucial para portabilidad
    ./configure --with-resample --with-pjproject-bundled --with-jansson-bundled && \
    make menuselect/menuselect menuselect-tree menuselect.makeopts && \
    menuselect/menuselect --disable BUILD_NATIVE menuselect.makeopts && \
    menuselect/menuselect --enable BETTER_BACKTRACES menuselect.makeopts && \
    menuselect/menuselect --enable codec_gsm menuselect.makeopts && \
    menuselect/menuselect --enable codec_opus menuselect.makeopts && \
    ### AÑADIDO PARA ARA/ODBC (Habilitar módulos) ### \
    menuselect/menuselect --enable res_odbc menuselect.makeopts && \
    menuselect/menuselect --enable res_config_odbc menuselect.makeopts && \
    menuselect/menuselect --enable func_odbc menuselect.makeopts && \
    ### Fin añadido ### \
    menuselect/menuselect --disable-category MENUSELECT_CORE_SOUNDS menuselect.makeopts && \
    menuselect/menuselect --disable-category MENUSELECT_MOH menuselect.makeopts && \
    menuselect/menuselect --disable-category MENUSELECT_EXTRA_SOUNDS menuselect.makeopts && \
    make -j$(nproc) && \
    make install && \
    make samples && \
    rm -rf /usr/src/asterisk

# Lógica condicional para G729 según arquitectura (INTACTA)
RUN if [ "$TARGETARCH" = "amd64" ]; then \
        wget http://asterisk.hosting.lv/bin/codec_g729-ast200-gcc4-glibc-x86_64-pentium4.so && \
        mv codec_g729* /usr/lib/asterisk/modules/codec_g729.so && \
        chmod +x /usr/lib/asterisk/modules/codec_g729.so; \
    else \
        echo "AVISO: Arquitectura ARM detectada ($TARGETARCH). Saltando instalación de binario G729 x86."; \
    fi

# Descargar sonidos
RUN mkdir -p /var/lib/asterisk/sounds/oml /var/lib/asterisk/sounds/en /var/lib/asterisk/sounds/es /var/lib/asterisk/moh /etc/asterisk/certs && \
    wget -q $ASTERISK_AUDIO_PROMPTS_EN -O - | tar xzv -C /var/lib/asterisk/sounds/en || true && \
    wget -q $ASTERISK_AUDIO_PROMPTS_ES -O - | tar xzv -C /var/lib/asterisk/sounds/es || true && \
    wget -q $OMNILEADS_AUDIO_PROMPTS -O - | tar xzv -C /var/lib/asterisk/sounds/oml || true && \
    wget -q $OMNILEADS_MOH -O - | tar xzv -C /var/lib/asterisk/moh || true

# --- PREPARACIÓN DE LIBRERÍAS ---
RUN mkdir -p /export-libs && \
    # Detectar path de librerias segun arquitectura
    if [ "$TARGETARCH" = "amd64" ]; then LIBPATH="/usr/lib/x86_64-linux-gnu"; else LIBPATH="/usr/lib/aarch64-linux-gnu"; fi && \
    cp $LIBPATH/libsqlite3.so.0 /export-libs/ && \
    cp $LIBPATH/libxml2.so.2 /export-libs/ && \
    cp $LIBPATH/libxslt.so.1 /export-libs/ && \
    cp $LIBPATH/libssl.so.3 /export-libs/ && \
    cp $LIBPATH/libcrypto.so.3 /export-libs/ && \
    cp $LIBPATH/libedit.so.2 /export-libs/ && \
    cp $LIBPATH/libbsd.so.0 /export-libs/ && \
    cp $LIBPATH/libcurl.so.4 /export-libs/

# Etapa 2: Runtime
FROM python:3.10-slim-trixie AS run

ENV LANG=en_US.utf8
ENV NOTVISIBLE="in users profile"

# Determinar arquitectura
ARG TARGETARCH

RUN apt update -qq && \
    apt install -y --no-install-recommends \
      binutils libicu-dev \
      ### AÑADIDO PARA ARA/ODBC (Drivers de ejecución) ### \
      # IMPORTANTE: Es mejor instalar esto por apt que copiar .so manualmente \
      # porque ODBC depende de plugins y configuraciones en /etc \
      unixodbc odbc-postgresql libpq5 && \
    apt autoremove -y && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*

# Copiar Asterisk
COPY --from=build /usr/local /usr/local
COPY --from=build /usr/lib/libasterisk* /usr/lib/
COPY --from=build /etc/asterisk /etc/asterisk/
COPY --from=build /var/lib/asterisk /var/lib/asterisk
COPY --from=build /var/log/asterisk /var/log/asterisk
COPY --from=build /var/spool/asterisk /var/spool/asterisk
COPY --from=build /usr/lib/asterisk /usr/lib/asterisk/
COPY --from=build /var/run/asterisk/ /var/run/asterisk/
COPY --from=build /usr/sbin/ast* /usr/sbin/

# Copiar librerias dinámicas "exportadas" manualmente
RUN if [ "$TARGETARCH" = "amd64" ]; then mkdir -p /usr/lib/x86_64-linux-gnu; else mkdir -p /usr/lib/aarch64-linux-gnu; fi
COPY --from=build /export-libs/ /usr/lib/x86_64-linux-gnu/
RUN if [ "$TARGETARCH" = "arm64" ]; then mv /usr/lib/x86_64-linux-gnu/* /usr/lib/aarch64-linux-gnu/ && rmdir /usr/lib/x86_64-linux-gnu; fi

COPY ./modules.conf /etc/asterisk/modules.conf

RUN chmod -R 750 /var/lib/asterisk /var/spool/asterisk /var/log/asterisk && \
    useradd -r -s /bin/false asterisk && \
    chown -R asterisk:asterisk /var/lib/asterisk /var/spool/asterisk /var/log/asterisk