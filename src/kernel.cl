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

ResultSha1 main_operation_sha1(Chunk* chunk, ResultSha1 prev_res){
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

        unsigned int tmp = rotate_left(prev_res.a, 5) + f + prev_res.e + k + chunk->data[i];
        prev_res.e = prev_res.d;
        prev_res.d = prev_res.c;
        prev_res.c = rotate_left(prev_res.b, 30);
        prev_res.b = prev_res.a;
        prev_res.a = tmp;
    }
    return prev_res;
}

ResultSha1 addResSha1(ResultSha1* x, ResultSha1* y){
    ResultSha1 result;
    result.a = x->a + y->a;
    result.b = x->b + y->b;
    result.c = x->c + y->c;
    result.d = x->d + y->d;
    result.e = x->e + y->e;
    return result;
}

// checks if the result is more probable
// returns the new result if candidate is better than best_prob, 0 otherwise
//!\ difficulty and probability_len must sum to less than 32
char is_more_probable(unsigned int candidate, unsigned char best_prob, unsigned char difficulty, unsigned char probability_len){
    if (((candidate >> (32 - difficulty - probability_len)) & 0xf)  > best_prob){
        return candidate >> (32 - difficulty - probability_len) & 0xf;
    }
    else if ((((-candidate) >> (32 - difficulty - probability_len)) & 0xf) > best_prob) {
        return (-candidate) >> (32 - difficulty - probability_len) & 0xf;
    }
    else {
        return 0;
    }
}


void prepare_final_chunk(Chunk* c, unsigned char padding_position, unsigned long int total_size){

    c->data[padding_position] = 0x80000000;
    // the size is encoded on 64 bits
    c->data[14] = total_size >> 32;
    c->data[15] = total_size & 0xffffffff;
    extend_chunk(c);
}


// fills the chunk with 9 ascii characters, and returns how many integers have been filled in the chunk
// or -1 if we generate a [\t\r\n ] character
char fill_chunk(Chunk* c, unsigned long nbr){
    unsigned char idx = 0;
    unsigned char i;
    unsigned char ascii_char;
    while (nbr){
        for(i=0; i<4; i++){
            ascii_char =  (nbr & 0x7f);
            if (ascii_char == 0x09 || ascii_char == 0x0a || ascii_char == 0x0d || ascii_char == 0x20){
                return -1;
            }
            c->data[idx] |= ascii_char << (i*8);
            nbr >>= 7;
        }
        idx += 1;
    }
    extend_chunk(c);
    return idx;
}

__kernel void explore_sha1(unsigned char difficulty,
    __global Chunk* random_chunks,
    ResultSha1 r_initial,
    unsigned int bit_len,
    __global unsigned char* finished,
    __global Chunk* result) {

    // we consider only the 4 most significant bits
    unsigned char proba_len = 4;

    unsigned int final_result_mask = ((1 << difficulty) - 1) << (32 - difficulty);

    // max of 32 chunks so the bit size can be coded within 2 ascii characters' bit size
    Chunk message_chunks[32];
    // systematically add the random chunk
    message_chunks[0] = random_chunks[get_global_id(0)];
    bit_len += 512;

    unsigned char message_chunks_idx = 1;
    // this isn't exactly a probability since it's not between 0 and 1, this is just the numerator's proba_len's most significant bits
    // of the probability (x/2³²)
    // we start with probability 1/2, which is guaranteed anyway (since we want either to maximize x or C(x)+1)
    unsigned char best_prob = 1 << (proba_len-1);

    ResultSha1 tmp_r;
    // add an initial random chunk's hash to have a different starting point per work-item
    // we don't need to extend the chunk, it's already extended
    tmp_r = main_operation_sha1(message_chunks, r_initial);
    ResultSha1 r = addResSha1(&tmp_r, &r_initial);

    unsigned long index = 0;
    unsigned char probability;
    Chunk most_probable_chunk;
    ResultSha1 most_probable_chunk_hash;

    // we have 1/2^(proba_len-1) to find the max probability, so the probability not to find it after n tries is 1-(1-1/2^(proba_len-1))^n
    // since we set proba_len = 4, we have 99.5% of chance to find it in only 40 tries
    while (best_prob != ((1 << proba_len) - 1) && index < (1ul<<63)){
        if (!*finished){
            Chunk c = {0};
            // skip forbidden values
            if (fill_chunk(&c, index) == -1){
                index += 1;
                continue;
            }
            tmp_r = main_operation_sha1(&c, r);
            tmp_r = addResSha1(&tmp_r, &r);

            probability = is_more_probable(tmp_r.a, best_prob, difficulty, proba_len);
            if (probability){
                // if we found a better probability, conserve the intermediate values, add the chunk and its hash
                // as a permanent solution, and break reset the loop
                best_prob = probability;
                most_probable_chunk = c;
            }
        }
        else {
            return;
        }
        index += 1;
    }
//    printf("nbr of turn until finding the max %d", index);

    // we found the most probable chunk we could, let's conserve its input and hash values
    r = tmp_r;
    message_chunks[message_chunks_idx] = most_probable_chunk;
    message_chunks_idx += 1;
    bit_len += 512;

    char padding_idx;
    index = 0;
    // we can fill up to 55 ascii characters, 9 will be enough for difficulties that are under 32-proba_len (2⁶³ possibilities)
    while (index < (1ul<<63) && !*finished){
        Chunk c = {0};
        padding_idx = fill_chunk(&c, index);
        // skip forbidden characters
        if (padding_idx == -1){
            index += 1;
            continue;
        }
        prepare_final_chunk(&c, padding_idx, bit_len + padding_idx * 32);

        tmp_r = main_operation_sha1(&c, r);
        tmp_r = addResSha1(&tmp_r, &r);
        if ((tmp_r.a & final_result_mask) == 0){
            // bingo!!
            // fill the buffer with the chunk and stop everything
            if (!*finished){
//                barrier(CLK_GLOBAL_MEM_FENCE);
                // notify other work-items that somebody has found the solution
                *finished = 1;
                unsigned char k;
                message_chunks[message_chunks_idx] = c;
                message_chunks_idx += 1;
                for(k=0; k<message_chunks_idx; k++){
                    result[k] = message_chunks[k];
                }
                return;
            }
        }
        index += 1;
    }
}



