#!/bin/sh

# Check for environment variables
if [ -z "$HF_TOKEN" ] || [ -z "$DATASET_ID" ]; then
    echo "Starting without backup functionality - missing HF_TOKEN or DATASET_ID"
    exit 1
fi

# Activate the virtual environment
. /easynode/venv/bin/activate

# Create the Python script for Hugging Face Hub synchronization
cat > /easynode/app/hf_sync.py << 'EOL'
from huggingface_hub import HfApi
import sys
import os
import tarfile
import tempfile

def manage_backups(api, repo_id, max_files=50):
    files = api.list_repo_files(repo_id=repo_id, repo_type="dataset")
    backup_files = [f for f in files if f.startswith('easynode_backup_') and f.endswith('.tar.gz')]
    backup_files.sort()
    
    if len(backup_files) >= max_files:
        files_to_delete = backup_files[:(len(backup_files) - max_files + 1)]
        for file_to_delete in files_to_delete:
            try:
                api.delete_file(path_in_repo=file_to_delete, repo_id=repo_id, repo_type="dataset")
                print(f'Deleted old backup: {file_to_delete}')
            except Exception as e:
                print(f'Error deleting {file_to_delete}: {str(e)}')

def upload_backup(file_path, file_name, token, repo_id):
    api = HfApi(token=token)
    try:
        api.upload_file(
            path_or_fileobj=file_path,
            path_in_repo=file_name,
            repo_id=repo_id,
            repo_type="dataset"
        )
        print(f"Successfully uploaded {file_name}")
        
        manage_backups(api, repo_id)
    except Exception as e:
        print(f"Error uploading file: {str(e)}")

# Download the latest backup
def download_latest_backup(token, repo_id):
    try:
        api = HfApi(token=token)
        files = api.list_repo_files(repo_id=repo_id, repo_type="dataset")
        backup_files = [f for f in files if f.startswith('easynode_backup_') and f.endswith('.tar.gz')]
        
        if not backup_files:
            print("No backup files found")
            return
            
        latest_backup = sorted(backup_files)[-1]
        
        with tempfile.TemporaryDirectory() as temp_dir:
            filepath = api.hf_hub_download(
                repo_id=repo_id,
                filename=latest_backup,
                repo_type="dataset",
                local_dir=temp_dir
            )
            
            if filepath and os.path.exists(filepath):
                with tarfile.open(filepath, 'r:gz') as tar:
                    tar.extractall('/easynode/app/')
                print(f"Successfully restored backup from {latest_backup}")
                
    except Exception as e:
        print(f"Error downloading backup: {str(e)}")

if __name__ == "__main__":
    action = sys.argv[1]
    token = sys.argv[2]
    repo_id = sys.argv[3]
    
    if action == "upload":
        file_path = sys.argv[4]
        file_name = sys.argv[5]
        upload_backup(file_path, file_name, token, repo_id)
    elif action == "download":
        download_latest_backup(token, repo_id)
EOL

# Download the latest backup on initial startup
echo "Downloading latest backup from HuggingFace..."
python hf_sync.py download "${HF_TOKEN}" "${DATASET_ID}"

# Data synchronization function
sync_data() {
    while true; do
        echo "Starting sync process at $(date)"
        
        if [ -d "/easynode/app/db" ]; then
            timestamp=$(date +%Y%m%d_%H%M%S)
            backup_file="easynode_backup_${timestamp}.tar.gz"
            
            tar -czf "/tmp/${backup_file}" db/
            
            echo "Uploading backup to HuggingFace..."
            python hf_sync.py upload "${HF_TOKEN}" "${DATASET_ID}" "/tmp/${backup_file}" "${backup_file}"
            
            rm -f "/tmp/${backup_file}"
        else
            echo "Data directory does not exist yet, waiting for next sync..."
        fi
        
        SYNC_INTERVAL=${SYNC_INTERVAL:-7200}
        echo "Next sync in ${SYNC_INTERVAL} seconds..."
        sleep $SYNC_INTERVAL
    done
}

# Start the sync process in the background
sync_data &

# Start the main application
exec npm run start
