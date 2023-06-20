# Use git grep to find all files containing '0.8.19'
files=$(git grep -l '0.8.19')

# Loop over files and replace '0.8.19' with '0.8.18'
for file in $files
do
  sed -i '' 's/0.8.19/0.8.18/g' "$file"
done

# # # Ignore test files
# find "test/" -type f -name "*.sol" | while read file; do
#   # Replace '.sol' extension with '.txt'
#   mv "$file" "${file%.sol}.txt"
# done

# mv "test/mock/MockLib.txt" "test/mock/MockLib.sol"

# Function to handle error
reset() {
    # find "test/" -type f -name "*.txt" | while read file; do
    #     # Replace '.sol' extension with '.txt'
    #     mv "$file" "${file%.txt}.sol"
    # done

    files=$(git grep -l '0.8.18')
    for file in $files
    do
        sed -i '' 's/0.8.18/0.8.19/g' "$file"
    done
}

trap 'reset' ERR

# pip3 install slither-analyzer
# pip3 install solc-select
# solc-select install 0.8.18
# solc-select use 0.8.18
FOUNDRY_PROFILE=dev forge build --skip test

slither test/mock/Slither.sol --show-ignored-findings --foundry-ignore-compile 

reset