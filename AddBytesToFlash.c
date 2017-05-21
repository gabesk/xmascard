#include <SDKDDKVer.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <tchar.h>

int main(int argc, char* argv[])
{
	int retcode = 0;
	
	if (argc != 5) {
		printf("usage: original_flash_image.bin padded.bin orig_size_bytes final_size_bytes\n");
		retcode = 1;
		goto End;
	}

	FILE* orig_fp = fopen(argv[1], "rb");
	if (orig_fp == NULL) {
		printf("ERROR: unable to open input file\n");
		retcode = 2;
		goto End;
	}

	int orig_size_bytes = atoi(argv[3]);
	int final_size_bytes = atoi(argv[4]);
	printf("original_flash_image: %s\n", argv[1]);
	printf("padded: %s\n", argv[1]);
	printf("orig_size_bytes: %d\n", orig_size_bytes);
	printf("final_size_bytes: %d\n", final_size_bytes);

	char* contents = malloc(final_size_bytes);
	if (contents == NULL) {
		printf("ERROR: unable to allocate %d bytes for PROM contents\n", final_size_bytes);
		fclose(orig_fp);
		retcode = 3;
		goto End;
	}

	memset(contents, 0xFF, final_size_bytes);

	size_t bytes_read = fread(contents, 1, orig_size_bytes, orig_fp);
	if (bytes_read != orig_size_bytes) {
		printf("ERROR: PROM is %d bytes large but only read %Iu bytes\n", orig_size_bytes, bytes_read);
		fclose(orig_fp);
		free(contents);
		retcode = 4;
		goto End;
	}

	if (fclose(orig_fp)) {
		printf("ERROR: Unable to close original file\n");
		free(contents);
		retcode = 5;
		goto End;
	}

	FILE* new_fp = fopen(argv[2], "wb");
	if (new_fp == NULL) {
		printf("ERROR: unable to open output file\n");
		free(contents);
		retcode = 6;
		goto End;
	}

	size_t bytes_written = fwrite(contents, 1, final_size_bytes, new_fp);
	if (bytes_written != final_size_bytes) {
		printf("ERROR: Unable to write all bytes to new PROM file. Intended to write %d bytes but only wrote %Iu bytes\n", final_size_bytes, bytes_written);
		free(contents);
		fclose(new_fp);
		retcode = 7;
		goto End;
	}

	if (fclose(new_fp)) {
		printf("ERROR: Unable to close new file\n");
		free(contents);
		retcode = 8;
		goto End;
	}

	free(contents);

	printf("Successfully padded file\n");

End:
    return retcode;
}

