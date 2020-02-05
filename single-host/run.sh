# Script para avaliação de performance de redes de contêineres
# by: Lucas Litter Mentz - 2019

# Definições
#SADC_PATH="/usr/lib64/sa/sadc"
#UNPRIVILEGED_USER="lucas:lucas"
SADC_PATH="/usr/lib/sysstat/sadc"
UNPRIVILEGED_USER="ubuntu:ubuntu"


user=`whoami`
drivers="host bridge overlay macvlan"

# Checar dependências
if ! test -e "$SADC_PATH"
then
	printf "\e[31;This script requires sysstat utilities (sar, sadc, sadf) to be installed\e[0m\n"
	exit 1
fi

if test "$user" != "root"
then
	printf "\e[31;This script requires super-user (root) permissions\e[0m\n"
	exit 1
fi

# Tudo está OK, fazer o trabalho.
printf "\e[37;4m;#### Building docker images...\e[0m\n"
docker build images/Baseline/ -t mentz/tcc:baseline
printf "\e[37;4m;#### Done building docker images!\e[0m\n"

for driver in $drivers
do
	printf "\e[37;4m;#### Removing left-over docker instances\e[0m\n"
	docker container rm -f `docker container ls -aq`
	printf "\e[37;4m;#### Done cleaning up docker instances!\e[0m\n"

	mkdir $driver/log >> /dev/null 2>&1
	rm $driver/log/saData.dat >> /dev/null 2>&1

	printf "\e[37;4m;#### Starting tests with %s driver\e[0m\n" $driver
	$SADC_PATH -F 1 121 $driver/log/saData.dat & >> /dev/null
	SADCPID=$!
	docker-compose --file $driver/docker-compose.yml up

	CREATED=`docker inspect --format="{{.Created}}" local_baseline_client`
	STARTED=`docker inspect --format="{{.State.StartedAt}}" local_baseline_client`
	FINISHED=`docker inspect --format="{{.State.FinishedAt}}" local_baseline_client`
	CREATED_TIMESTAMP=$(($(date --date=$CREATED +%s%N)/1000000))
	STARTED_TIMESTAMP=$(($(date --date=$STARTED +%s%N)/1000000))
	FINISHED_TIMESTAMP=$(($(date --date=$FINISHED +%s%N)/1000000))
	printf "Created:  %s\n" $CREATED > $driver/log/time.txt
	printf "Started:  %s\n" $STARTED >> $driver/log/time.txt
	printf "Finished: %s\n" $FINISHED >> $driver/log/time.txt
	printf "Creation time:  %s ms\n" $((STARTED_TIMESTAMP-CREATED_TIMESTAMP)) >> $driver/log/time.txt
	printf "Execution time: %s ms\n" $((FINISHED_TIMESTAMP-STARTED_TIMESTAMP)) >> $driver/log/time.txt
	printf "Total time:     %s ms\n" $((FINISHED_TIMESTAMP-CREATED_TIMESTAMP)) >> $driver/log/time.txt

	printf "Waiting data collection to end"
	while jobs %% >> /dev/null 2>&1; do
		printf "."
		sleep 1
	done
	printf " Done!\n"

	sadf -j -- -u ALL -b $driver/log/saData.dat > $driver/log/cpu_usage.json
	sadf -g -- -u ALL -b $driver/log/saData.dat > $driver/log/cpu_usage.svg
	chown -R $UNPRIVILEGED_USER $driver/log
	printf "\e[37;4m;#### Done testing with %s driver!\e[0m;\n" $driver
done
