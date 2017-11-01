#!/bin/bash

for f in $(ls Deployment/); do
	if [[ -d Deployment/${f} ]]; then
		for filename in $(ls -v Deployment/${f}); do
			if [[ $filename == *[@]* ]]
			then
			echo "Issue found"
			else
			echo $filename
			fi
	   done
	fi
done
