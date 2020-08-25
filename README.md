# Sha1-zeros-finder
Given a string s, find a suffix string such as SHA1(s+suffix) gives a digest with n leading zeros

It runs the search on the first GPU found with openCL

**src/main.rs** gives an example on how to use it

* The input string can be of any size, up to 2⁶⁴-1 bits
  * But it must be padded to be a multiple of 512, using the **padding_to_512_multiple(bytes)** function
* *difficulty* must be in the range [1, 28] for now, I will increase it later
* *work_items* is the number of workitems to run on the GPU at once
