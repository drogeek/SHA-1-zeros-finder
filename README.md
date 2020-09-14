# Sha1-zeros-finder
Given a string s, find a suffix string such as SHA1(s+suffix) gives a digest with n leading zeros

It runs the search on the first GPU found with openCL

**src/main.rs** gives an example on how to use it

* The input string can be of any size, up to 2⁶⁴-1 bits
  * But it must be padded to be a multiple of 512, using the **padding_to_512_multiple(bytes)** function
* *difficulty* must be in the range [1, 64-proba_len] for now, I will increase it later, with proba_len, the bits reserved to increase the probability.
P(overflow | proba_len most significant bits are 1) = 1-1/2^proba_len and therefore the probability not to find a solution after m tries is 1 – (1-(2^proba_len-1)/2^(difficulty+proba_len)) ^ m
* *work_items* is the number of workitems to run on the GPU at once
