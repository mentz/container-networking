# Script para avaliação de performance de redes de contêineres
# by: Lucas Litter Mentz - 2019

# Definições
#SADC_PATH="/usr/lib64/sa/sadc"
#UNPRIVILEGED_USER="lucas:lucas"
SADC_PATH="/usr/lib/sysstat/sadc"
UNPRIVILEGED_USER="ubuntu:ubuntu"


user=`whoami`
# TODO: Adicionar rotinas para redes Overlay, Contiv e Calico
networks="host bridge overlay macvlan"

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

for network in $networks
do
	printf "\e[37;4m;#### Removing left-over docker instances\e[0m\n"
	docker container rm -f `docker container ls -aq`
	printf "\e[37;4m;#### Done cleaning up docker instances!\e[0m\n"

	rm $network/log/saData.dat >> /dev/null 2>&1
	printf "\e[37;4m;#### Starting tests with %s network\e[0m\n" $network
	$SADC_PATH -F 1 121 $network/log/saData.dat & >> /dev/null
	SADCPID=$!
	docker-compose --file $network/docker-compose.yml up

	CREATED=`docker inspect --format="{{.Created}}" local_baseline_client`
	STARTED=`docker inspect --format="{{.State.StartedAt}}" local_baseline_client`
	FINISHED=`docker inspect --format="{{.State.FinishedAt}}" local_baseline_client`
	CREATED_TIMESTAMP=$(($(date --date=$CREATED +%s%N)/1000000))
	STARTED_TIMESTAMP=$(($(date --date=$STARTED +%s%N)/1000000))
	FINISHED_TIMESTAMP=$(($(date --date=$FINISHED +%s%N)/1000000))
	printf "Created:  %s\n" $CREATED > $network/log/time.txt
	printf "Started:  %s\n" $STARTED >> $network/log/time.txt
	printf "Finished: %s\n" $FINISHED >> $network/log/time.txt
	printf "Creation time:  %s ms\n" $((STARTED_TIMESTAMP-CREATED_TIMESTAMP)) >> $network/log/time.txt
	printf "Execution time: %s ms\n" $((FINISHED_TIMESTAMP-STARTED_TIMESTAMP)) >> $network/log/time.txt
	printf "Total time:     %s ms\n" $((FINISHED_TIMESTAMP-CREATED_TIMESTAMP)) >> $network/log/time.txt

	printf "Waiting data collection to end"
	while jobs %% >> /dev/null 2>&1; do
		printf "."
		sleep 1
	done
	printf " Done!\n"

	sadf -j -- -u ALL -b $network/log/saData.dat > $network/log/cpu_usage.json
	sadf -g -- -u ALL -b $network/log/saData.dat > $network/log/cpu_usage.svg
	chown -R $UNPRIVILEGED_USER $network/log
	printf "\e[37;4m;#### Done testing with %s network!\e[0m;\n" $network
done
