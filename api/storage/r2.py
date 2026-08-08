from __future__ import annotations

from typing import BinaryIO, Optional

import boto3
from botocore.client import Config

from .config import config
from .interfaces import IStorageProvider


class R2Storage(IStorageProvider):
    """
    Cloudflare R2 implementation using the S3-compatible API.
    """

    def __init__(self):
        self.client = boto3.client(
            "s3",
            endpoint_url=config.r2_endpoint,
            aws_access_key_id=config.r2_access_key,
            aws_secret_access_key=config.r2_secret_key,
            region_name=config.r2_region,
            config=Config(signature_version="s3v4"),
        )

    def upload_file(
        self,
        bucket: str,
        remote_path: str,
        file: BinaryIO,
        *,
        upsert: bool = True,
        content_type: Optional[str] = None,
    ):
        print(f"[R2 UPLOAD] bucket={bucket}")
        print(f"[R2 UPLOAD] key={remote_path}")
        print(">>> R2Storage.upload_file() CALLED")
        extra = {}

        if content_type:
            extra["ContentType"] = content_type

        # Use put_object instead of upload_fileobj for better control over
        # content type and to avoid multipart upload overhead for small files.
        self.client.put_object(
            Bucket=config.r2_bucket,
            Key=remote_path,
            Body=file,
            ContentType=content_type or "application/octet-stream",
        )

        return True

    def download_file(
        self,
        bucket: str,
        remote_path: str,
    ) -> bytes:
        print(f"[R2 DOWNLOAD] bucket={bucket}")
        print(f"[R2 DOWNLOAD] key={remote_path}")

        obj = self.client.get_object(
            Bucket=config.r2_bucket,
            Key=remote_path,
        )

        return obj["Body"].read()

    def delete_file(
        self,
        bucket: str,
        remote_path: str,
    ):

        self.client.delete_object(
            Bucket=config.r2_bucket,
            Key=remote_path,
        )

        return True

    def list_buckets(self):
        return [config.r2_bucket]

    def create_bucket(
        self,
        bucket: str,
        public: bool = False,
    ):
        """
        R2 buckets are usually created from the Cloudflare dashboard.
        """
        raise NotImplementedError(
            "Bucket creation is managed from Cloudflare."
        )

    def get_url(
        self,
        bucket: str,
        remote_path: str,
        expires_in: Optional[int] = None,
    ) -> str:

        print("R2 PUBLIC URL =", config.r2_public_url)
        print("R2 PATH =", remote_path)

        if expires_in is None:

            return (
                f"{config.r2_public_url.rstrip('/')}/"
                f"{remote_path}"
            )

        return self.client.generate_presigned_url(
            "get_object",
            Params={
                "Bucket": config.r2_bucket,
                "Key": remote_path,
            },
            ExpiresIn=expires_in,
        )