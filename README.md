# pocket2wallabag
```
                                ___
 __   __   __        ___ ___   |_  | ▄   ▄       █ █       ▗▖          ▗▄▖
|__) /  \ /  ` |__/ |__   |   / __/  █ ▄ █ ▗▞▀▜▌ █ █ ▗▞▀▜▌ ▐▌   ▗▞▀▜▌ ▐▌ ▐▌
|    \__/ \__, |  \ |___  |  /____/  █▄█▄█ ▝▚▄▟▌ █ █ ▝▚▄▟▌ ▐▛▀▚▖▝▚▄▟▌  ▝▀▜▌
                                                 █ █       ▐▙▄▞▘      ▐▙▄▞▘
```

## Description

**A PowerShell script to migrate Pocket CSV export data to wallabag format.**

With the impending death of Mozilla's [Pocket](https://getpocket.com/farewell) read it later platform, I put this stuff together to transition Pocket export data into a self-hosted [wallabag](https://wallabag.org) instance.
Although wallabag does include Pocket importers, both by linking to your Pocket account and by uploading the Pocket CSV export files, neither was robust enough to import my 12K saves with tags.
So I put this repo together to solve that gap and finish my transition to using wallabag.
Hopefully it helps someone else, too.

**Repo URL:** [https://github.com/qu13t0ne/pocket2wallabag](https://github.com/qu13t0ne/pocket2wallabag)

**Process Summary**

- (Optional) Add a custom tag to 'Favorited' records in Pocket
- Export Pocket data as CSV
- Convert Pocket CSV to wallabag v2 JSON data format for more robust import capabilities
- Import converted data to wallabag instance using wallabag CLI commands
- Read!

**Contents**
- [pocket2wallabag](#pocket2wallabag)
  - [Description](#description)
  - [Add Tag to Pocket Favorites](#add-tag-to-pocket-favorites)
  - [Export Pocket Data](#export-pocket-data)
  - [Convert Data Using Convert-Pocket2Wallabag.ps1](#convert-data-using-convert-pocket2wallabagps1)
  - [Import Converted Data to wallabag](#import-converted-data-to-wallabag)
  - [Metadata](#metadata)
  - [Links and References](#links-and-references)

## Add Tag to Pocket Favorites

Unfortunately, the Pocket CSV export data doesn't include whether an item was 'Favorited', which is something I made extensive use of during my years of Pocket usage, with over 600 favorited articles.

Solution: Before export, add a custom tag to favorited items using the Pocket API.

## Export Pocket Data

- Export your data from Pocket per https://getpocket.com/export.
- Download the data one ready.
- Unzip the compressed file to expose the CSVs.

## Convert Data Using Convert-Pocket2Wallabag.ps1

About the script:

> This script processes one or more CSV files exported from Pocket, located in a given input directory.
> It performs the following operations:
>   - Parses CSV lines safely, accounting for unquoted fields and embedded commas in titles and URLs.
>   - Combines all entries into a single dataset.
>   - Converts Unix timestamps to ISO 8601 datetime format.
>   - Splits items into archived and unread sets.
>   - Outputs JSON in chunks of a given size (default 1000 items per file).
>   - Adds a unique tag in the format 'pocket-to-wallabag-YYYYMMDDHHMMSS' to each item's tag list.
>   - If a `FavoriteTag` is provided, items that include that tag will be marked as `"is_starred": 1`.
>   - Writes output files into a subdirectory under the input folder named after the generated tag.
>   - Output files are named using the format: `{tag}_{unread/archive}_00.json`, etc.

Run the script against the downloaded Pocket CSVs.
If you created a custom tag designating Pocket favorites, provide it as `-FavoriteTag <tag>`.
File chunking size should be fine, but if needed you can modify it with the `-ChunkSize` param.

Processed files will be output to a subdirectory of wherever the input files were, with directory name `pocket2wallabag-YYYYMMDDHHMMSS`.

## Import Converted Data to wallabag

Copy the converted files to the server or container running the wallabag application.
I'm running wallabag using Docker Compose (see my setup: https://github.com/qu13t0ne/outpost).
So, I copied the processed files to the host server, then temporarily mounted the files directory to the main wallabag container via my docker-compose file.
Then I accessed the shell inside the container using `docker exec -it <container> sh`.

Once in the shell of the container/server (depending on your setup), the following will iterate through all processed datafiles and upload them to your wallabag instance. Modify the `DIRECTORY_TO_UPLOAD` and `WALLABAG_USER` as appropriate, and ensure you're executing from the directory `/var/www/wallabag`.
```sh
DIRECTORY_TO_UPLOAD=/path/to/files
WALLABAG_USER=wallabag
mkdir $DIRECTORY_TO_UPLOAD/processed
for file in $DIRECTORY_TO_UPLOAD/* ; do
php bin/console wallabag:import $WALLABAG_USER $file --env=prod --importer=v2
mv $file $DIRECTORY_TO_UPLOAD/processed/
done
```

Obviously, this may take a while to process depending on how many URLs you're migrating.
Just let it run.

## Metadata

**Created By Mike Owens** | [GitHub](https://github.com/qu13t0ne) ~ [GitLab](https://gitlab.com/qu13t0ne) ~ [Bluesky](https://bsky.app/profile/qu13t0ne.bsky.social)~ [Mastodon](https://infosec.exchange/@qu13t0ne)

**License: [MIT](LICENSE)**

## Links and References

- https://getpocket.com/farewell
- https://wallabag.org
- https://github.com/qu13t0ne/outpost

*Disclosure: ChatGPT was used for support in drafting these scripts.*
