# Install Dependencies
travis_run sudo apt-get install clang-format-3.6

# Change to source directory. This directory should have its own .clang-format config file
travis_run cd $CI_SOURCE_PATH
travis_run ls -la

# Run clang-format
echo "Running clang-format"
find . -name '*.h' -or -name '*.hpp' -or -name '*.cpp' | xargs clang-format-3.6 -i -style=file

echo "Showing changes in code style:"
git --no-pager diff

# Make sure no changes have occured in repo
if ! git diff-index --quiet HEAD --; then
    # changes
    echo "clang-format test failed: changes required to comply to formatting rules. See diff above.";
    exit -1
fi

echo "Passed clang-format test"
