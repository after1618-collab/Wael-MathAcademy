from __future__ import annotations

from typing import BinaryIO, Optional

from supabase import Client

from .interfaces import IStorageProvider


class SupabaseStorage(IStorageProvider):
    """
    Concrete implementation for Supabase Storage.
    """

    def __init__(self, client: Client):
        self.client = client

    def upload_file(
        self,
        bucket: str,
        remote_path: str,
        file: BinaryIO,
        *,
        upsert: bool = True,
        content_type: Optional[str] = None,
    ):
        print(">>> SupabaseStorage.upload_file() CALLED")
        options = {
            "x-upsert": str(upsert).lower()
        }

        if content_type:
            options["content-type"] = content_type

        return (
            self.client
            .storage
            .from_(bucket)
            .upload(
                remote_path,
                file,
                options,
            )
        )

    def download_file(
        self,
        bucket: str,
        remote_path: str,
    ) -> bytes:
        return (
            self.client
            .storage
            .from_(bucket)
            .download(remote_path)
        )

    def delete_file(
        self,
        bucket: str,
        remote_path: str,
    ):
        return (
            self.client
            .storage
            .from_(bucket)
            .remove([remote_path])
        )

    def list_buckets(self):
        buckets = self.client.storage.list_buckets()
        return [bucket.name for bucket in buckets]

    def create_bucket(
        self,
        bucket: str,
        public: bool = False,
    ):
        return self.client.storage.create_bucket(
            bucket,
            {"public": public},
        )

    def get_url(
        self,
        bucket: str,
        remote_path: str,
        expires_in: Optional[int] = None,
    ) -> str:

        storage = self.client.storage.from_(bucket)

        if expires_in is None:
            return storage.get_public_url(remote_path)

        return storage.create_signed_url(
            remote_path,
            expires_in,
        )