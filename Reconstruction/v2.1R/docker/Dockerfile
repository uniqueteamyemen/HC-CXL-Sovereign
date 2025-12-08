FROM python:3.11-slim

WORKDIR /app

COPY ../2_build/HC-CXL_v2.1R_SOVEREIGN_PACKAGE.zip /app/

RUN apt-get update && apt-get install -y unzip && apt-get clean

RUN unzip HC-CXL_v2.1R_SOVEREIGN_PACKAGE.zip -d /app/hc-cxl

CMD ["python3", "-c", "print('HC-CXL v2.1R Sovereign Package Loaded Successfully')"]
