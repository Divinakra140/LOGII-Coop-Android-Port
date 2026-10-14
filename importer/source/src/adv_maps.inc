// maps that render cleanly in the 512x288 view (automated still + moving
// scan of every map with 2+ exits: no black areas, seams or tearing)
// v41: minus maps with a dialog / story scene on a trigger or on arrival
// (automated event scan: every trigger stepped on + A pressed) and 8/34
// (crashed in the scan)
const unsigned char kAdvMaps[][2] = {{10,10},{10,11},{10,14},{10,15},{10,2},{10,22},{10,3},{10,32},{10,6},{10,7},{10,9},{12,10},{12,11},{12,12},{12,13},{12,15},{13,2},{13,4},{13,5},{13,6},{13,9},{2,1},{2,2},{2,26},{2,31},{2,35},{2,36},{2,37},{2,38},{2,40},{2,7},{4,53},{4,54},{4,56},{4,71},{4,72},{4,74},{4,75},{4,77},{4,91},{4,92},{4,93},{6,60},{7,16},{7,21},{7,24},{7,4},{7,5},{7,7},{8,10},{8,12},{8,14},{8,16},{8,17},{8,18},{8,19},{8,23},{8,25},{8,3},{8,31},{8,32},{8,33},{8,41},{8,42},{8,47},{8,48},{8,7},{8,8},{8,9}};
