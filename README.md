# MoveIt Continous Integration
Common Travis CI configuration for MoveIt! project

- Uses Docker for all Distros
  - Travis does not currently support Ubuntu 16.04
  - Based on OSRF's pre-build ROS Docker container to save setup time
  - Uses MoveIt's pre-build Docker container to additionally save setup time
- Simple - only contains features needed for MoveIt!
- Clean Travis log files - looks similiar to a regular .travis.yml file
- Runs tests for the current repo, e.g. if testing moveit\_core only runs tests for moveit\_core
- Builds into install space
- Prevents Travis from timing out and from running out of log space, even for huge builds (all of MoveIt!)
