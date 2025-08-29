#Running Environment
FROM fedora:latest

#Me
LABEL maintainer="Brian Miller <brian@phospher.com>"

# Update the container
#RUN dnf -y update

# Basic tools
RUN dnf install -y wget libicu vim-enhanced rpmdevtools fedora-packager fedora-review gcc

# Setup
RUN usermod -a -G mock root

# .NET
RUN wget https://dot.net/v1/dotnet-install.sh
RUN bash dotnet-install.sh --channel 9.0

# Path
ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/root/.dotnet/

# small prep stuf
RUN echo "set mouse-=a" > /root/.vimrc

# dooyet
CMD ["/bin/bash"]
