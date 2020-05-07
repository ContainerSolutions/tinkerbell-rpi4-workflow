#!/bin/sh
registry=$1
if [[ -z $registry ]]
then
	echo "Provide target registry. Example create-images.sh 127.0.0.1"  
	exit 1
fi

location=$(dirname $0)

for dir in $(find $location -name Dockerfile -printf '%h\n'|sort)
do
  image=${dir#*[0-9][0-9]-}
  docker build -t $registry/$image $dir/
  docker push $registry/$image
done

echo "Done."

