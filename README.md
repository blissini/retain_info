## Synopsis

A script to quickly gather information/stats from a GWAVA Retain database.
Currently supported database drivers are Mysql and Oracle

## Example usage
Download the script:
```bash
wget https://raw.githubusercontent.com/blissini/retain_info/master/retain_info.sh
```

Either run the script on the server:
```bash
./retain_info.sh
```

Or run it through an ssh session:
```bash
ssh <host> "bash -s" < ./retain_info.sh
```
