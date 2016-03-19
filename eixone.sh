
ls | grep -i ^$1 | head -n $(( $2 + 1 )) | tail -n 1 | xargs -l1 eix -e
