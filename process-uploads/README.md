
# Description

The process-uploads.sh script will process uploads from the ci pipelines connected to the mm-toolbox (packages) and meta-imagebuilder (images) repositores. It is intended to run via cron as an unpriviliged user. In the rest of this document, it is assumed that user is named `uploader`.

The process-uploads.sh script is silent when it does nothing; when it updates a package repository and/or an image directory it will print some output.

## Packages:

The script looks for uploads in the `~uploader/package-uploads/` directory. It creates a staging area for the repository in `~uploaders/package-repo-staging/${branch}`. After generating the necessary repository files, it will rsync the `~uploader/package-repo-staging/${branch}` directory to `/var/www/html/snapshots/packages/${arch}/generic` (main branch) or `/var/www/html/experimental/packages/${branch}/${arch}/generic` (any other branch), with the --delete argument.

If there are no errors, it will then move processed uploads to the `~uploader/package-uploads-processed/` directory. If there are any errors, the script will revert to `no-op` mode (see below) and leave the directory in the
`~uploader/package-uploads/` directory.

## Images:

The script looks for uploads in the `~uploader/image-uploads/` directory. If the uploaded directory contains at least as many entries as the destination directory, it will rsync the uploaded directory to `/var/www/html/snapshots/images/${profile}/${device}` (main branch) or `/var/www/html/experimental/images/${branch}/${profile}/${device}` (any other branch), with the --delete argument.

If there are no errors, it will then move processed uploads to the `~uploader/image-uploads-processed/` directory. If there are any errors, the script will revert to 'no-op` mode (see below) and leave the directory in the `~uploader/image-uploads/` directory.

## No-op mode

When run with the `--noop` argument, the script will update the package repository staging area and run the rsync to the public repository directory with the `--dry-run` argument. It will not move the processed directories from `~uploader/package-uploads/` to `~uploader/package-uploads-processed/`. Similarly for images: the rsync to the destination directory will be run with the `--dry-run` argument, and the processed directories will not be moved from `~uploader/image-uploads` to `~uploader/image-uploads-processed/`.

# Installation

## Create mkhash

The 'mkhash.c' file needs to be compiled (leave the binary in this directory):

<pre>
$ gcc mkhash.c -o mkhash
</pre>

## Create usign

The 'usign' program needs to be compiled and copied to this directory:

<pre>
$ git clone https://git.openwrt.org/project/usign.git usign.git
$ cd usign.git/
$ cmake .
$ make
$ mv usign ..
$ rm -rf usign.git
</pre>

## Copy everything to the server

Then copy all the files in this directory to the machine that will run the cron job, and install the cron job. Make sure the `/home/uploader` directory exists and is owned by the `uploader` user.

## Create a usign keypair

Generate a usign keypair and make the public key available to the world:

<pre>
$ ./usign -G -c "Your Signing Key Description" -s secret.key -p public.key
$ mkdir ~uploader/keys; chmod 700 ~uploader/keys
$ mv secret.key ~uploader/keys/
$ mv public.key ~uploader/keys/
$ sudo cp ~uploader/keys/public.key /var/www/html/
</pre>

## Install a cron job

To run the script periodically, install a cron job, for instance:

<pre>
# crontab -u uploader -l
* * * * * /usr/local/glue/process-uploads/process-uploads.sh
</pre>
