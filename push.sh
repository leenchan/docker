#!/bin/sh
find ./ -name .DS_Store|while read LINE
do
	rm -f "$LINE">/dev/null
done
git add *
git commit -a --allow-empty-message -m ''
git push origin master
