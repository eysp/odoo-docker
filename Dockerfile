FROM ubuntu:20.04
MAINTAINER Elico Corp <webmaster@elico-corp.com>

# Define build constants
ENV GIT_BRANCH=14.0 \
  PYTHON_BIN=python3 \
  SERVICE_BIN=odoo-bin

# Set timezone to UTC
RUN ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

# Generate locales
RUN apt update \
  && apt -yq install locales \
  && locale-gen en_US.UTF-8 \
  && update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8

# Install APT dependencies
ADD sources/apt.txt /opt/sources/apt.txt
RUN apt update \
  && awk '! /^ *(#|$)/' /opt/sources/apt.txt | xargs -r apt install -yq

# Create the odoo user
RUN useradd --create-home --home-dir /opt/odoo --no-log-init odoo

# Switch to user odoo to create the folders mapped with volumes, else the
# corresponding folders will be created by root on the host
USER odoo

# If the folders are created with "RUN mkdir" command, they will belong to root
# instead of odoo! Hence the "RUN /bin/bash -c" trick.
RUN /bin/bash -c "mkdir -p /opt/odoo/{etc,sources/odoo,additional_addons,data,ssh}"

# Add Odoo sources and remove .git folder in order to reduce image size
WORKDIR /opt/odoo/sources
RUN git clone --depth=1 https://github.com/odoo/odoo.git -b $GIT_BRANCH \
  && rm -rf odoo/.git

ADD sources/odoo.conf /opt/odoo/etc/odoo.conf
ADD auto_addons /opt/odoo/auto_addons

User 0

# Install Odoo python dependencies
RUN sed -i s/20.9.0/21.12.0/g /opt/odoo/sources/odoo/requirements.txt
RUN pip3 install -r /opt/odoo/sources/odoo/requirements.txt

# Install extra python dependencies
ADD sources/pip.txt /opt/sources/pip.txt
RUN pip3 install -r /opt/sources/pip.txt

# Install wkhtmltopdf based on QT5
ADD https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6-1/wkhtmltox_0.12.6-1.focal_arm64.deb \
  /opt/sources/wkhtmltox.deb
RUN apt update \
  && apt install -yq xfonts-base xfonts-75dpi ttf-wqy-zenhei \
  && dpkg -i /opt/sources/wkhtmltox.deb

# Install postgresql-client
RUN apt update && apt install -yq lsb-release
RUN curl https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
RUN sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
RUN apt update && apt install -yq postgresql-client

# Startup script for custom setup
ADD sources/startup.sh /opt/scripts/startup.sh

# Provide read/write access to odoo group (for host user mapping). This command
# must run before creating the volumes since they become readonly until the
# container is started.
RUN chmod -R 775 /opt/odoo && chown -R odoo:odoo /opt/odoo

VOLUME [ \
  "/opt/odoo/etc", \
  "/opt/odoo/additional_addons", \
  "/opt/odoo/data", \
  "/opt/odoo/ssh", \
  "/opt/scripts" \
]

# Use README for the help & man commands
ADD README.md /usr/share/man/man.txt
# Remove anchors and links to anchors to improve readability
RUN sed -i '/^<a name=/ d' /usr/share/man/man.txt
RUN sed -i -e 's/\[\^\]\[toc\]//g' /usr/share/man/man.txt
RUN sed -i -e 's/\(\[.*\]\)(#.*)/\1/g' /usr/share/man/man.txt
# For help command, only keep the "Usage" section
RUN from=$( awk '/^## Usage/{ print NR; exit }' /usr/share/man/man.txt ) && \
  from=$(expr $from + 1) && \
  to=$( awk '/^    \$ docker-compose up/{ print NR; exit }' /usr/share/man/man.txt ) && \
  head -n $to /usr/share/man/man.txt | \
  tail -n +$from | \
  tee /usr/share/man/help.txt > /dev/null

# Use dumb-init as init system to launch the boot script
ADD https://github.com/Yelp/dumb-init/releases/download/v1.2.5/dumb-init_1.2.5_arm64.deb /opt/sources/dumb-init.deb
RUN dpkg -i /opt/sources/dumb-init.deb
ADD bin/boot /usr/bin/boot
ENTRYPOINT [ "/usr/bin/dumb-init", "/usr/bin/boot" ]
CMD [ "help" ]

ENV ODOO_TIMEZONE=Asia/Shanghai
RUN sed -i "s/fonts\.googleapis\.com/fonts.lug.ustc.edu.cn/g" \
  `grep 'fonts\.googleapis\.com' -rl /opt/odoo/sources/odoo/addons`

# Expose the odoo ports (for linked containers)
EXPOSE 8069 8072
