#!/bin/sh
case "$SSH_ORIGINAL_COMMAND" in
*\&*)
echo "Rejected 1"
;;
*\;*)
echo "Rejected 2"
;;
rsync*)
$SSH_ORIGINAL_COMMAND
;;
*true*)
echo $SSH_ORIGINAL_COMMAND
;;
*)
echo "Rejected 3"
;;
esac
