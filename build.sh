#!/bin/sh

docker build --file=Dockerfile --tag=tel_acd_base:dev_20.9 --target=run .
      .