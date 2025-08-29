#Running Environment
FROM ubuntu:focal

#Me
LABEL maintainer="Brian Miller <brian@phospher.com>"

ARG DEBIAN_FRONTEND=noninteractive

# Update the container
RUN apt-get -y update
RUN apt-get -y upgrade

# Basic tools
RUN apt-get install --no-install-recommends --no-install-suggests -y bash zip unzip curl vim jq wget language-pack-en ca-certificates bc
RUN apt-get install --no-install-recommends --no-install-suggests -y inetutils-ping time
RUN apt-get install --no-install-recommends --no-install-suggests -y gawk sysstat openssh-client

# Build tools
RUN apt-get install --no-install-recommends --no-install-suggests -y build-essential binutils lintian debhelper dh-make devscripts git
RUN apt-get update

# .NET
RUN wget https://dot.net/v1/dotnet-install.sh
RUN bash dotnet-install.sh --channel 9.0

# Path
ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/root/.dotnet/


# small prep stuf
RUN echo "set mouse-=a" > /root/.vimrc


# dooyet
CMD ["/bin/bash"]
