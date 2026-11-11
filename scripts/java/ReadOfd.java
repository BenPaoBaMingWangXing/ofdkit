import java.nio.file.Paths;
import java.util.List;

import org.ofdrw.core.basicStructure.pageObj.layer.CT_Layer;
import org.ofdrw.core.basicStructure.pageObj.layer.PageBlockType;
import org.ofdrw.core.basicStructure.pageObj.layer.block.ImageObject;
import org.ofdrw.core.basicStructure.pageObj.layer.block.PathObject;
import org.ofdrw.core.basicStructure.pageObj.layer.block.TextObject;
import org.ofdrw.core.text.TextCode;
import org.ofdrw.reader.OFDReader;
import org.ofdrw.reader.PageInfo;

/**
 * Opens an OFD package with ofdrw (the reference Java implementation) and walks
 * every page and layer. If ofdrw can parse the package and report the objects
 * we wrote, the package is readable by a real implementation, not just by the
 * checker that produced it.
 */
public final class ReadOfd {

    public static void main(String[] args) throws Exception {
        if (args.length < 1) {
            System.err.println("usage: ReadOfd <file.ofd>");
            System.exit(2);
        }
        int totalText = 0;
        int totalPath = 0;
        int totalImage = 0;
        int totalOther = 0;
        int textCodes = 0;
        StringBuilder sample = new StringBuilder();

        try (OFDReader reader = new OFDReader(Paths.get(args[0]))) {
            System.out.println("pages=" + reader.getNumberOfPages());
            List<PageInfo> pages = reader.getPageList();
            for (PageInfo info : pages) {
                System.out.println("page " + info.getIndex() + " size=" + info.getSize());
                for (CT_Layer layer : info.getAllLayer()) {
                    for (PageBlockType block : layer.getPageBlocks()) {
                        if (block instanceof TextObject) {
                            totalText++;
                            TextObject text = (TextObject) block;
                            List<TextCode> codes = text.getTextCodes();
                            if (codes != null) {
                                textCodes += codes.size();
                                for (TextCode code : codes) {
                                    if (sample.length() < 40 && code.getContent() != null) {
                                        sample.append(code.getContent());
                                    }
                                }
                            }
                        } else if (block instanceof PathObject) {
                            totalPath++;
                        } else if (block instanceof ImageObject) {
                            totalImage++;
                        } else {
                            totalOther++;
                        }
                    }
                }
            }
        }
        System.out.println("textObjects=" + totalText);
        System.out.println("textCodes=" + textCodes);
        System.out.println("pathObjects=" + totalPath);
        System.out.println("imageObjects=" + totalImage);
        System.out.println("otherObjects=" + totalOther);
        System.out.println("sampleText=" + sample);
    }
}
