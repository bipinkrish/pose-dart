# Pose

This is a `dart` implementation of its [python counterpart](https://github.com/sign-language-processing/pose/tree/master/src/python) with limited features

This repository helps developers interested in Sign Language Processing (SLP) by providing a complete toolkit for working with poses. It includes a file format with Python and Javascript readers and writers, which hopefully makes its usage simple.

### File Format Structure

The file format is designed to accommodate any pose type, an arbitrary number of people, and an indefinite number of frames. 
Therefore it is also very suitable for video data, and not only single frames.

At the core of the file format is `Header` and a `Body`.

* The header for example contains the following information:

    - The total number of pose points. (How many points exist.)
    - The exact positions of these points. (Where do they exist.)
    - The connections between these points. (How are they connected.)


## Features


## Getting started


## Usage


## Additional information

