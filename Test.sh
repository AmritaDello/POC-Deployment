#!/bin/bash

for f in $(ls Deployment/); do
		echo "Entering into $f"
	if [[ -d Deployment/${f} ]]; then
		for filename in `ls Deployment/$f | sort -V`; do
			if [[ $filename == *[@]* ]]
			then
			echo "Issue found"
			fi
	   done
	fi
done
