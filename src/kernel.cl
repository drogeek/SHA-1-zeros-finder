// create finalChunk with size 16 instead
// get rid of the padding and size when solution found

typedef struct {
    char data[4];
    unsigned char size;
}Utf8Char;

typedef struct {
    unsigned int a;
    unsigned int b;
    unsigned int c;
    unsigned int d;
    unsigned int e;
}ResultSha1;

typedef struct {
    unsigned int data[80];
}Chunk;



unsigned int rotate_left(unsigned int x, char shift){
    return x << shift | x >> (32 - shift);
}

void extend_chunk(Chunk* chunk){
    char i;
    for(i=16;i<80;i++){
        chunk->data[i] = rotate_left(chunk->data[i-3] ^ chunk->data[i-8] ^ chunk->data[i-14] ^ chunk->data[i-16], 1);
    }
}

// data_size < (64-8-1) bytes, because we need space for the message_size (in bits) and space for at least the separator byte
Chunk gen_final_chunk(char* data, unsigned char data_size, unsigned long message_size) {
    Chunk result = {0};
    unsigned char i, j;
    //copy data to the chunk

    for(i=0; i<data_size/4; i++){
        for (j=0; j<4; j++){
            result.data[i] |= data[4*i+j] << (32-(j+1)*8);
        }
    }
    for(j=0; j<data_size%4; j++){
        result.data[i] |= data[4*i+j] << (32-(j+1)*8);
    }
    //separator byte
    result.data[i] |= 0x80 << (32-(j+1)*8);

    //zero padding until the 64-8-1th byte
    for (i=i+1; i<14; i++){
        result.data[i] = 0;
    }

    //append message_size in the end, byte by byte

    unsigned long mask = 0xffffffff;
    for(j=0; j<2; j++){
        result.data[i+j] = (unsigned int)(message_size & (mask << (64 - 32 * (j+1))));
    }
    extend_chunk(&result);
    return result;
}

//typedef struct{
//    char value;
//    char finished;
//}AsciiGen;
//
//typedef struct{
//    char size;
//    // there are 54 possible ascii characters (64 - (1 two bytes character + 8 bytes of size))
//    AsciiGen sequence[54];
//}AsciiSeqGen;
//
//void reset_asciiGen(AsciiGen* g){
//    g->value = 0;
//    g->finished = 0;
//}
//
//void init_asciiSeqGen(AsciiSeqGen* g, char size){
//    unsigned char i;
//    for(i=0; i<size; i++){
//        reset_asciiGen(&g->sequence[i]);
//    }
//    g->size = size;
//}
//
//
//
//void nextAscii(AsciiGen* g){
//    g->value += 1;
//    if (g->value == 0x7f) {
//        g->finished = 1;
//    }
//}
//
//
////increase the ascii generator sequence
////returns 0 if the sequence is over, 1 otherwise
//char nextAsciiSeq(AsciiSeqGen* seq){
//    unsigned char i = 0;
//    printf("prout\n");
//    while (seq->sequence[i].finished == 1) {
//        i+=1;
//    }
//    if (i == seq->size) {
//        return 0;
//    }
//    else{
//        //increase the ith generator
//        nextAscii(&seq->sequence[i]);
//
//        if (!seq->sequence[i].finished){
//            //reset previous ascii generators
//            unsigned char j;
//            for(j=0; j<i; j++){
//                reset_asciiGen(&seq->sequence[j]);
//            }
//        }
//    }
//    return 1;
//}

// seq size must be a multiple of 2
// chunk must be initialized to 0
//void AsciiSeq2Chunk(Chunk* chunk, AsciiSeqGen* seq, unsigned int size){
//    unsigned char i, j, k;
//    for(i=0; i<seq->size/4; i++){
//        chunk->data[i] = 0;
//        for(j=0; j<4; j++){
//            chunk->data[i] |= seq->sequence[i*4 + j].value << (32 - (j+1)*8);
//        }
//    }
//    // at this point, there are 2 scenarios, either 2 bytes are left, or none
//    // if 2 bytes are left, we put them in the upper part, and the lower part is 0xc080
//    // if 0 bytes are left, we put 0xc080 in the upper part of the next part of the chunk
//    // we add the size in the end, which should be on only 2 bytes
//    chunk->data[i] = 0;
//    char left_overs = seq->size%4;
//    if (left_overs) {
//        for(j=0; j<left_overs; j++){
//            chunk->data[i] |= seq->sequence[i*4 + j].value << (32 - (j+1)*8);
//        }
//        chunk-> data[i] |= 0xc080;
//    }
//    else {
//        i+=1;
//        chunk -> data[i] = 0xc0800000;
//    }
//    //every bytes in between are supposed to be already 0
//    chunk->data[63] = size;
//    extend_chunk(&chunk);
//}

// fill the chunk with ascii characters up to 64/7=9 ascii characters, ending with a multi-bytes character of
// size 2 (constant) whose last byte is 0x8000 (constraint from both utf-8 and the padding expected by sha-1)
// also put the message_size encoding in the end, and then extend the chunk as defined by sha-1
//!\ we expect the chunk to be initialized at 0 !
void fill_chunk_with_constraints(Chunk* chunk, char size, unsigned int message_size, unsigned long index){
    unsigned char i, j, k, l;
    for(i=0; i<size/4; i++){
        for(j=0; j<4; j++){
            chunk->data[i] |= (index & 0x7f) << j*8;
            index >>= 7;
        }
    }
    // at this point, there are 2 scenarios, either 2 bytes are left, or none
    // if 2 bytes are left, we put them in the upper part, and the lower part is 0xc080
    // if 0 bytes are left, we put 0xc080 in the upper part of the next part of the chunk
    // we add the size in the end, which should be on only 2 bytes
    char left_overs = size%4;
    if (left_overs) {
        for(j=0; j<left_overs; j++){
            chunk->data[i] |= (index & 0x7f) << (j*8 + 16);
            index >>= 7;
        }
        chunk-> data[i] |= 0xc880;
        //printf("%x\n", chunk ->data[i]);
    }
    else {
        chunk -> data[i] = 0xc8800000;
    }
    //every bytes in between are supposed to be already 0
    chunk->data[15] = message_size;
    extend_chunk(chunk);
}

// data is assumed to be of size 512/8=64 bytes
Chunk gen_chunk(char* data) {
    Chunk result = {0};
    char i, j;
    for (i=0; i<16; i++){
        for (j=0; j<4; j++){
            result.data[i] |= data[4*i+j]<<(32-(j+1)*8)<< (32 - (j+1)*8);
        }
    }
    extend_chunk(&result);
    return result;
}





unsigned char is_utf8(unsigned char* potential_utf8_str, unsigned int size) {
    unsigned int start_idx = 0;
    while (size != 0) {
        unsigned char first_byte = potential_utf8_str[start_idx];
        // check if it's ascii and not {\n\r\t }
        if ((first_byte & 0x80) >> 7 == 0) {
            if (first_byte ==  0x09 ||
                first_byte ==  0x0d ||
                first_byte ==  0x0a ||
                first_byte ==  0x20) {
                return 0;
            }
            // skip 1 byte
            start_idx += 1;
            size -= 1;
        }
        else if ((first_byte & 0xe0) >> 5 == 0b110) {
            start_idx += 1;
            size -= 1;
            // it's a 2 bytes character, check if there is a second byte
            if ((potential_utf8_str[start_idx] & 0xf0) >> 6 == 0b10) {
                start_idx += 1;
                size -= 1;
            }
            else {
                return 0;
            }
        }
        else if ((first_byte & 0xf0) >> 4 == 0b1110) {
            start_idx += 1;
            size -= 1;
            // it's a 3 bytes character, check if there are 2 additional bytes
            char i;
            for (i=0; i<2; i++){
                if ((potential_utf8_str[start_idx + i] & 0xf0) >> 6 != 0b10) {
                    return 0;
                }
            }

            if (first_byte == 0xe0){
                if (potential_utf8_str[start_idx] < 0xa0) {
                    return 0;
                }
            }
            else if (first_byte == 0xed){
                 if (potential_utf8_str[start_idx] > 0x9f) {
                     return 0;
                 }
            }
            else {
                start_idx += 2;
                size -= 2;
            }
        }
        else if ((first_byte & 0xf0) >> 4 == 0xf) {
            start_idx += 1;
            size -= 1;
            // it's a 4 bytes character, check if there are 3 additional bytes
            char i;
            for (i=0; i<3; i++){
                if ((potential_utf8_str[start_idx] & 0xf0) >> 6 == 0b10) {
                    start_idx += 1;
                    size -= 1;
                }
                else{
                    return 0;
                }
            }
        }
        // it doesn't start with a valid byte
        else {
            return 0;
        }
    }
    return 1;
}


//get utf8 character at index i
//it assumes to have values from 0 to 1112064, which is the number of utf8 characters
//also the data field inside the returned value should be freed
//!\ no check is done on the given value!
Utf8Char get_utf8_char(unsigned int i){
    Utf8Char result;
    if (i<0x80){
        result.data[0] = (char)i;
        result.size = 1;
        return result;
    }

    else if (i<0x800){
        result.data[0] = (char)(0xc0 | (i>>6));
        result.data[1] = (char)(0x80 | (i&0x3f));
        result.size = 2;
        return result;
    }
    else if (i<0x10000-(0xe000 - 0xd800)){
        if (i >= 0xd800 && i < 0xe000){
            i+=(0xe000 - 0xd800);
        }
        result.data[0] = (char)(0xe0 | (i>>12));
        result.data[1] = (char)(0x80 | ((i>>6) & 0x3f));
        result.data[2] = (char)(0x80 | (i&0x3f));
        result.size = 3;
        return result;
    }
    else{
        i += (0xe000 - 0xd800);
        result.data[0] = (char)(0xf0 | (i >> 18));
        result.data[1] = (char)(0x80 | ((i>>12) & 0x3f));
        result.data[2] = (char)(0x80 | ((i>>6) & 0x3f));
        result.data[3] = (char)(0x80 | (i&0x3f));
        result.size = 4;
        return result;
    }

}

ResultSha1 main_operation_sha1(Chunk chunk, ResultSha1 prev_res){
    unsigned char i;
    for (i=0; i<80; i++){
        unsigned int f, k;

        if (i<=19) {
            f = (prev_res.b & prev_res.c)  | ((-prev_res.b-1) & prev_res.d);
            k = 0x5A827999;
        }

        else if (i<=39){
            f = prev_res.b ^ prev_res.c ^ prev_res.d;
            k = 0x6ED9EBA1;
        }

        else if (i<=59){
            f = (prev_res.b & prev_res.c) | (prev_res.b & prev_res.d) | (prev_res.c & prev_res.d);
            k = 0x8F1BBCDC;
        }

        else {
            f = prev_res.b ^ prev_res.c ^ prev_res.d;
            k = 0xCA62C1D6;
        }

        unsigned int tmp = rotate_left(prev_res.a, 5) + f + prev_res.e + k + chunk.data[i];
        prev_res.e = prev_res.d;
        prev_res.d = prev_res.c;
        prev_res.c = rotate_left(prev_res.b, 30);
        prev_res.b = prev_res.a;
        prev_res.a = tmp;
    }
    return prev_res;
}

ResultSha1 addResSha1(ResultSha1 x, ResultSha1 y){
    ResultSha1 result;
    result.a = x.a + y.a;
    result.b = x.b + y.b;
    result.c = x.c + y.c;
    result.d = x.d + y.d;
    result.e = x.e + y.e;
    return result;
}

// checks if the result is more probable
// returns the new result if candidate is better than best_prob, 0 otherwise
char is_more_probable(unsigned int candidate, unsigned char best_prob, unsigned char difficulty){
//    printf("candidate %x\n", ((candidate >> (32 - difficulty - 4)) & 0xf));
//    printf("-candidate %x\n", ((-candidate >> (32 - difficulty - 4)) & 0xf));
    if (((candidate >> (32 - difficulty - 4)) & 0xf)  > best_prob){
        return candidate >> (32 - difficulty - 4) & 0xf;
    }
    else if ((((-candidate) >> (32 - difficulty -4)) & 0xf) > best_prob) {
        return (-candidate) >> (32 - difficulty -4) & 0xf;
    }
    else {
        return 0;
    }
}




__kernel void explore_sha1(unsigned char difficulty, __global Chunk* random_chunks, ResultSha1 r_initial, unsigned int bit_len, __global unsigned char* finished, __global Chunk* result) {
    printf("Let's explore a lil\n");
    // we consider only the 4 most significant bits
    unsigned int final_result_mask = ((1 << difficulty) - 1) << (32 - difficulty);
    // max of 32 chunks so the bit size can be coded within 2 ascii characters' bit size
    Chunk message_chunks[32];
    // systematically add the random chunk
    message_chunks[0] = random_chunks[get_global_id(0)];
    unsigned char message_chunks_idx = 1;
    // this isn't exactly a probability since it's not between 0 and 1, this is just the numerator's 4 most significant bits
    // of the probability (x/2³²)
    // we start with probability 1/2, which is guaranteed anyway (since we want either to maximize x or C(x)+1)
    unsigned char best_prob = 0x8;

    // add an initial random chunk's hash to have a different starting point per work-item
    ResultSha1 r = addResSha1(main_operation_sha1(random_chunks[get_global_id(0)], r_initial), r_initial);
    bit_len += 512;

//    if (r.a >> (32-difficulty) == 0){
    unsigned int i, j;
    // since 1 on 2 multiple of 8 are not valid ascii characters (because the 8th bit is always 0), we have to increase
    // the size by 16 instead of 8, and therefore add at least 2 ascii characters each time
    // the size is therefore inferior to 2^(9+5) and is a multiple of 16
    i=bit_len;
    while (i<0x7f00) {
        for(j=16; j<127; j+=16){
            // if we don't have enough space to put ascii characters… we give up!
            if(i+j-bit_len > 432){
                return;
            }
            Chunk c = {0};
            unsigned long index;
            unsigned char probability;
            ResultSha1 tmp_r;

            unsigned long max_index = 1ul << (7*(i+j - bit_len-16)/8);
            // fill a maximum of 9 of the first ascii characters with values from 0 to 2⁶³
            while (index <= max_index) {
                if (!finished[0]){
                    Chunk c = {0};
                    fill_chunk_with_constraints(&c, (i+j - bit_len - 16)/8, i+j, index);
                    tmp_r = addResSha1(main_operation_sha1(c, r), r);
                    if ((tmp_r.a & final_result_mask) == 0){
                        // bingo!!
                        // fill the buffer with the chunk and stop everything

                        printf("I found it biatch!!\n");
                        printf("%08x\n", tmp_r.a);
                        if (!finished[0]){
                            // notify other work-items that somebody has found the solution
                            finished[0] = 1;
                            unsigned char k;
                            message_chunks[message_chunks_idx] = c;
                            message_chunks_idx += 1;
                            for(k=0; k<message_chunks_idx; k++){
                                result[k] = message_chunks[k];
                            }
                            return;
                        }
                    }

                    // no need to check if it's already at the max
                    if (best_prob != 0xf) {
                        probability = is_more_probable(tmp_r.a, best_prob, difficulty);
                        if (probability){
                            // if we found a better probability, conserve the intermediate values, add the chunk and its hash
                            // as a permanent solution, and break reset the loop
                            best_prob = probability;
                            r = tmp_r;
                            message_chunks[message_chunks_idx] = c;
                            message_chunks_idx += 1;
                            i += 512;
                            bit_len += 512;
                            index = 0;
                        }
                        else {
                            index += 1;
                        }
                    }
                    else {
                        index += 1;
                    }
                }
                else {
                    //another work-item found the solution, quit
                    return;
                }

            }
        }
        i += 256;
    }
}


//__kernel void explore_sha1(unsigned char difficulty, __global Chunk* random_chunks, ResultSha1 r_initial, unsigned int bit_len, __global unsigned char* finished, __global Chunk* result) {
//    AsciiSeqGen seq;
//    init_asciiSeqGen(&seq, 3);
//    char remaining, i, j;
//    for(i=0; i<100; i++){
//        remaining = nextAsciiSeq(&seq);
//        printf("remaining %d", remaining);
//        if(remaining){
//            for(i=0; i<seq.size; i++){
//                printf("%x", seq.sequence[i]);
//            }
//        }
//        printf("\n");
//    }

//    printf("Let's explore a lil");
//    // we consider only the 4 most significant bits
//    unsigned int final_result_mask = 0xf0000000;
//    // max of 32 chunks so the bit size can be coded within 2 ascii characters' bit size
//    Chunk message_chunks[32];
//    // systematically add the random chunk
//    message_chunks[0] = random_chunks[get_global_id(0)];
//    unsigned char message_chunks_idx = 1;
//    // this isn't exactly a probability since it's not between 0 and 1, this is just the numerator's 4 most significant bits
//    // of the probability (x/2³²)
//    // we start with probability 1/2, which is guaranteed anyway (since we want either to maximize x or C(x)+1)
//    unsigned char best_prob = 0x8;
//
//    // add an initial random chunk's hash to have a different starting point per work-item
//    ResultSha1 r = addResSha1(main_operation_sha1(random_chunks[get_global_id(0)], r_initial), r_initial);
//    bit_len += 512;
//
////    if (r.a >> (32-difficulty) == 0){
//    unsigned int i, j;
//    unsigned long max_index = 1ul << 63;
//    // since 1 on 2 multiple of 8 are not valid ascii characters (because the 8th bit is always 0), we have to increase
//    // the size by 16 instead of 8, and therefore add at least 2 ascii characters each time
//    // the size is therefore inferior to 2^(9+5) and is a multiple of 16
//    for(i=bit_len; i<0x7f00; i+= 256){
//        for(j=16; j<127; j+=16){
//            Chunk c = {0};
//            unsigned long index;
//            unsigned char probability;
//            ResultSha1 tmp_r;
//
//            // fill a maximum of 9 of the first ascii characters with values from 0 to 2⁶³
//            while (index <= max_index) {
//                if (!finished[0]){
//                    Chunk c = {0};
//                    fill_chunk_with_constraints(&c, (i+j - bit_len - 16)/8, i+j, index);
//                    tmp_r = addResSha1(main_operation_sha1(c, r), r);
//                    if ((tmp_r.a & final_result_mask) == 0){
//                        // bingo!!
//                        // fill the buffer with the chunk and stop everything
//
//                        printf("I found it biatch!!");
//                        printf("%x", tmp_r.a);
//                        if (!finished[0]){
//                            // notify other work-items that somebody has found the solution
//                            finished[0] = 1;
//                            unsigned char k;
//                            message_chunks[message_chunks_idx] = c;
//                            message_chunks_idx += 1;
//                            for(k=0; k<message_chunks_idx; k++){
//                                result[k] = message_chunks[k];
//                            }
//                            return;
//                        }
//                    }
//
//                    // no need to check if it's already at the max
//                    if (best_prob != 0xf) {
//                        probability = is_more_probable(tmp_r.a, best_prob, difficulty);
//            //            printf("proba %x, tmp_r %x, best_prob %x", probability, tmp_r.a, best_prob);
//                        if (probability){
//                            printf("found a better alternative");
//                            // if we found a better probability, conserve the intermediate values, add the chunk and its hash
//                            // as a permanent solution, and break reset the loop
//                            best_prob = probability;
//                            r = tmp_r;
//                            message_chunks[message_chunks_idx] = c;
//                            message_chunks_idx += 1;
//                            bit_len += 512;
//                            index = 0;
//                        }
//                        else {
//                            index += 1;
//                        }
//                    }
//                }
//                else {
//                    //another work-item found the solution, quit
//                    return;
//                }
//
//            }
//         }
//    }
//}