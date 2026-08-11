#
# NOTE: THIS DOCKERFILE IS GENERATED VIA "apply-templates.sh"
#
# PLEASE DO NOT EDIT IT DIRECTLY.
#

FROM mcr.microsoft.com/windows/nanoserver:ltsc2022

SHELL ["cmd", "/S", "/C"]

# PATH isn't actually set in the Docker image, so we have to set it from within the container
USER ContainerAdministrator
RUN setx /m PATH "C:\mongodb\bin;%PATH%"
USER ContainerUser
# doing this first to share cache across versions more aggressively

COPY --from=mongo:8.3.8-windowsservercore-ltsc2022 \
	C:\\Windows\\System32\\msvcp140.dll \
	C:\\Windows\\System32\\msvcp140_1.dll \
	C:\\Windows\\System32\\vcruntime140.dll \
	C:\\Windows\\System32\\vcruntime140_1.dll \
	C:\\Windows\\System32\\

# https://docs.mongodb.org/master/release-notes/8.3/
ENV MONGO_VERSION 8.3.8
# 07/21/2026, https://github.com/mongodb/mongo/tree/35e8c8a57f78157ed9fac1a9e90ee6c1818adab6

COPY --from=mongo:8.3.8-windowsservercore-ltsc2022 C:\\mongodb C:\\mongodb
RUN mongod --version

VOLUME C:\\data\\db C:\\data\\configdb

EXPOSE 27017
CMD ["mongod", "--bind_ip_all"]
